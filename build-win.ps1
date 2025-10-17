Param(
  [string]$Projects = 'all',      # all|llama|whisper|sd (comma-separated)
  [string]$Devices  = 'auto',     # auto|cpu|vulkan|cuda|opencl|all (comma-separated)
  [int]$Jobs        = [int]::Parse($env:NUMBER_OF_PROCESSORS),
  [switch]$Clean,
  [string]$LlamaSrc = '',
  [string]$WhisperSrc = '',
  [string]$SDSrc = ''
)

$ROOT      = (Get-Location).Path
$EXTERN    = Join-Path $ROOT 'external'
$BUILD     = Join-Path $ROOT 'build'
$OUT       = Join-Path $ROOT 'EVA_BACKEND'
$OS_ID     = 'win'

# Pinned references (only checked/warned)
$LLAMA_EXPECT_REF = 'b6746'
$WHISPER_EXPECT_TAG = 'v1.8.1'
$SD_EXPECT_REF = '0585e2609d26fc73cde0dd963127ae585ca62d49'

function Resolve-Arch {
  $arch = $env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
  switch -Regex ($arch) {
    '^(AMD64|X64)$'   { return 'x86_64' }
    '^(x86|X86)$'     { return 'x86_32' }
    '^(ARM64)$'       { return 'arm64' }
    '^(ARM)$'         { return 'arm32' }
    default           { return 'x86_64' }
  }
}

function Test-Cmd([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Can-Vulkan {
  if ($env:VULKAN_SDK) { return $true }
  if (Test-Cmd 'glslc') { return $true }
  $vkInc = Join-Path ${env:ProgramFiles} 'VulkanSDK'
  try {
    if (Test-Path $vkInc) {
      $hit = Get-ChildItem -Path $vkInc -Recurse -ErrorAction SilentlyContinue -Filter 'vulkan.h' | Select-Object -First 1
      if ($hit) { return $true }
    }
  } catch {}
  return $false
}

function Can-CUDA {
  if (Test-Cmd 'nvcc') { return $true }
  if (Test-Path 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA') { return $true }
  return $false
}

function Can-OpenCL {
  if (Test-Path "$env:WINDIR\System32\OpenCL.dll") { return $true }
  if (Test-Cmd 'clinfo') { return $true }
  return $false
}

function Resolve-Devices([string]$req) {
  $set = New-Object System.Collections.Generic.HashSet[string]
  if ($req -eq 'auto') {
    $set.Add('cpu') | Out-Null
    if (Can-Vulkan) { $set.Add('vulkan') | Out-Null }
  } elseif ($req -eq 'all') {
    $set.Add('cpu') | Out-Null
    if (Can-Vulkan) { $set.Add('vulkan') | Out-Null }
    if (Can-CUDA) { $set.Add('cuda') | Out-Null }
    if (Can-OpenCL) { $set.Add('opencl') | Out-Null }
  } else {
    foreach ($d in $req.Split(',')) { $null = $set.Add($d.Trim()) }
  }
  return ,@($set)
}

function Resolve-Src([string]$name,[string]$cli,[string]$envName,[string[]]$candidates) {
  if ($cli) { return $cli }
  $envVal = [Environment]::GetEnvironmentVariable($envName)
  if ($envVal) { return $envVal }
  foreach ($c in $candidates) {
    if (Test-Path (Join-Path $c 'CMakeLists.txt')) { return $c }
  }
  return $null
}

function Show-Version([string]$label,[string]$path,[string]$ExpectRef,[string]$ExpectTag) {
  if (-not (Test-Cmd 'git')) { Write-Host "[$label] $path (git not available)"; return }
  if (-not (Test-Path (Join-Path $path '.git'))) { Write-Host "[$label] $path (not a git repo)"; return }
  $head = ''
  $tag = ''
  try { $head = (git -C $path rev-parse --short HEAD) } catch {}
  try { $tag = (git -C $path describe --tags --exact-match) } catch {}
  $have = if ($tag) { $tag } else { $head }
  $note = ''
  if ($ExpectTag) {
    if ($tag -and $tag -eq $ExpectTag) { $note = "(matches $ExpectTag)" } else { $note = "(want $ExpectTag, have $have)" }
  } elseif ($ExpectRef) {
    if ($head -and $head.StartsWith($ExpectRef)) { $note = "(matches $ExpectRef)" } else { $note = "(want $ExpectRef, have $have)" }
  }
  Write-Host "[$label] $path ref=$have $note"
}

function Get-Generator([string]$arch) {
  if (Test-Cmd 'ninja') { return @{ G='Ninja'; A=$null } }
  $vs = 'Visual Studio 17 2022'
  $a = switch ($arch) {
    'x86_64' { 'x64' }
    'x86_32' { 'Win32' }
    'arm64'  { 'ARM64' }
    'arm32'  { 'ARM' }
    default  { 'x64' }
  }
  return @{ G=$vs; A=$a }
}

function Invoke-CMakeConfigure([string]$src,[string]$bdir,[hashtable]$gen,[string[]]$defs) {
  New-Item -ItemType Directory -Force -Path $bdir | Out-Null
  $args = @('-S', $src, '-B', $bdir, '-D', 'BUILD_SHARED_LIBS=OFF', '-D', 'CMAKE_POSITION_INDEPENDENT_CODE=ON', '-D', 'CMAKE_BUILD_TYPE=Release')
  if ($gen.G) { $args += @('-G', $gen.G) }
  if ($gen.A) { $args += @('-A', $gen.A) }
  foreach ($d in $defs) { $args += $d }
  & cmake @args
}

function Invoke-CMakeBuild([string]$bdir,[string[]]$targets) {
  $args = @('--build', $bdir, '--config', 'Release')
  if ($Jobs -gt 0) { $args += @('--parallel', "$Jobs") }
  if ($targets -and $targets.Count -gt 0) { $args += @('--target'); $args += $targets }
  & cmake @args
}

function Copy-Binary([string]$bdir,[string]$tgt,[string]$outdir) {
  New-Item -ItemType Directory -Force -Path $outdir | Out-Null
  $exe = "$tgt.exe"
  $candidates = @()
  $candidates += (Join-Path $bdir $exe)
  $candidates += (Join-Path (Join-Path $bdir 'bin') $exe)
  $candidates += (Join-Path (Join-Path $bdir 'Release') $exe)
  $candidates += (Join-Path (Join-Path (Join-Path $bdir 'bin') 'Release') $exe)
  $candidates += (Join-Path $bdir $tgt)
  $candidates += (Join-Path (Join-Path $bdir 'bin') $tgt)
  foreach ($c in $candidates) {
    if (Test-Path $c) { Copy-Item $c -Destination $outdir -Force; Write-Host "Copied $(Split-Path $c -Leaf) -> $outdir"; return }
  }
  Write-Warning "Could not locate built binary '$tgt' under $bdir"
}

function Get-AvailableTargets([string]$bdir) {
  try { return ((& cmake --build $bdir --config Release --target help) -join "`n") } catch { return '' }
}
function Assert-BackendEnabled([string]$bdir,[string]$device,[string]$project) {
  $cache = Join-Path $bdir 'CMakeCache.txt'
  if (-not (Test-Path $cache)) { return }
  $txt = Get-Content -Raw -LiteralPath $cache
  switch ($device) {
    'vulkan' {
      if ($txt -notmatch 'GGML_VULKAN:BOOL=ON|GGML_VULKAN:BOOL=TRUE') {
        Write-Warning "$project [$device]: GGML_VULKAN not enabled by CMake; falling back to CPU. Ensure Vulkan SDK installed and VULKAN_SDK is set."
      } elseif ($txt -notmatch 'Vulkan_FOUND:INTERNAL=1|Vulkan_FOUND:BOOL=TRUE') {
        Write-Warning "$project [$device]: Vulkan not found (Vulkan_FOUND=FALSE); check VULKAN_SDK and build environment."
      }
    }
    'cuda' {
      if ($txt -notmatch 'GGML_CUDA:BOOL=ON|GGML_CUDA:BOOL=TRUE') {
        Write-Warning "$project [$device]: GGML_CUDA not enabled; check CUDA toolkit and CMake logs."
      }
    }
    'opencl' {
      if ($txt -notmatch 'GGML_OPENCL:BOOL=ON|GGML_OPENCL:BOOL=TRUE') {
        Write-Warning "$project [$device]: GGML_OPENCL not enabled; ensure OpenCL headers/libs available."
      }
    }
  }
}


function Build-Llama([string]$device,[string]$arch) {
  $src = Resolve-Src 'llama.cpp' $LlamaSrc 'LLAMA_SRC' @((Join-Path $ROOT 'llama.cpp'), (Join-Path $EXTERN 'llama.cpp'))
  if (-not $src) { throw "llama.cpp source not found. Provide -LlamaSrc or set LLAMA_SRC or place repo at .\llama.cpp or .\external\llama.cpp." }
  Show-Version 'llama.cpp' $src $LLAMA_EXPECT_REF ''
  $bdir = Join-Path (Join-Path $BUILD 'llama.cpp') $device
  if ($Clean) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $bdir }
  $defs = @('-D', 'LLAMA_CURL=OFF', '-D', 'LLAMA_BUILD_TESTS=OFF', '-D', 'LLAMA_BUILD_EXAMPLES=ON', '-D', 'LLAMA_BUILD_SERVER=ON')
  switch ($device) {
    'vulkan' {  $defs += @('-D','GGML_VULKAN=ON','-D','SD_VULKAN=ON') }
    'cuda'   {  $defs += @('-D','GGML_CUDA=ON','-D','SD_CUDA=ON','-D','GGML_NATIVE=OFF') }
    'opencl' {  $defs += @('-D','GGML_OPENCL=ON','-D','SD_OPENCL=ON') }
    default  { $defs += @('-D','GGML_VULKAN=OFF','-D','GGML_CUDA=OFF','-D','GGML_OPENCL=OFF') }
  }
  $gen = Get-Generator $arch
  Invoke-CMakeConfigure $src $bdir $gen $defs
  if ($device -in @('vulkan','cuda','opencl')) { Assert-BackendEnabled $bdir $device 'llama.cpp' }
  $help = Get-AvailableTargets $bdir
  $targets = @()
  foreach ($t in @('llama-server','llama-quantize','llama-tts')) { if ($help -match [regex]::Escape($t)) { $targets += $t } }
  if ($targets.Count -eq 0) { Invoke-CMakeBuild $bdir @() } else { Invoke-CMakeBuild $bdir $targets }
  $out = Join-Path (Join-Path (Join-Path (Join-Path $OUT $arch) $OS_ID) $device) 'llama.cpp'
  Copy-Binary $bdir 'llama-server' $out
  Copy-Binary $bdir 'llama-quantize' $out
  Copy-Binary $bdir 'llama-tts' $out
}
function Build-Whisper([string]$device,[string]$arch) {
  $src = Resolve-Src 'whisper.cpp' $WhisperSrc 'WHISPER_SRC' @((Join-Path $ROOT 'whisper.cpp'), (Join-Path $EXTERN 'whisper.cpp'))
  if (-not $src) { throw "whisper.cpp source not found. Provide -WhisperSrc or set WHISPER_SRC or place repo at .\whisper.cpp or .\external\whisper.cpp." }
  Show-Version 'whisper.cpp' $src '' $WHISPER_EXPECT_TAG
  $bdir = Join-Path (Join-Path $BUILD 'whisper.cpp') $device
  if ($Clean) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $bdir }
  $defs = @('-D','WHISPER_BUILD_TESTS=OFF','-D','WHISPER_BUILD_EXAMPLES=ON')
  switch ($device) {
    'vulkan' {  $defs += @('-D','GGML_VULKAN=ON','-D','SD_VULKAN=ON') }
    'cuda'   {  $defs += @('-D','GGML_CUDA=ON','-D','SD_CUDA=ON','-D','GGML_NATIVE=OFF') }
    'opencl' {  $defs += @('-D','GGML_OPENCL=ON','-D','SD_OPENCL=ON') }
    default  { $defs += @('-D','GGML_VULKAN=OFF','-D','GGML_CUDA=OFF','-D','GGML_OPENCL=OFF') }
  }
  $gen = Get-Generator $arch
  Invoke-CMakeConfigure $src $bdir $gen $defs
  if ($device -in @('vulkan','cuda','opencl')) { Assert-BackendEnabled $bdir $device 'whisper.cpp' }
  Invoke-CMakeBuild $bdir @('whisper-cli')
  $out = Join-Path (Join-Path (Join-Path (Join-Path $OUT $arch) $OS_ID) $device) 'whisper.cpp'
  Copy-Binary $bdir 'whisper-cli' $out
}
function Build-SD([string]$device,[string]$arch) {
  $src = Resolve-Src 'stable-diffusion.cpp' $SDSrc 'SD_SRC' @((Join-Path $ROOT 'stable-diffusion.cpp'), (Join-Path $EXTERN 'stable-diffusion.cpp'))
  if (-not $src) { throw "stable-diffusion.cpp source not found. Provide -SDSrc or set SD_SRC or place repo at .\stable-diffusion.cpp or .\external\stable-diffusion.cpp." }
  Show-Version 'stable-diffusion.cpp' $src $SD_EXPECT_REF ''
  $bdir = Join-Path (Join-Path $BUILD 'stable-diffusion.cpp') $device
  if ($Clean) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $bdir }
  $defs = @()
  switch ($device) {
    'vulkan' {  $defs += @('-D','GGML_VULKAN=ON','-D','SD_VULKAN=ON') }
    'cuda'   {  $defs += @('-D','GGML_CUDA=ON','-D','SD_CUDA=ON','-D','GGML_NATIVE=OFF') }
    'opencl' {  $defs += @('-D','GGML_OPENCL=ON','-D','SD_OPENCL=ON') }
    default  { $defs += @('-D','GGML_VULKAN=OFF','-D','GGML_CUDA=OFF','-D','GGML_OPENCL=OFF') }
  }
  $gen = Get-Generator $arch
  Invoke-CMakeConfigure $src $bdir $gen $defs
  if ($device -in @('vulkan','cuda','opencl')) { Assert-BackendEnabled $bdir $device 'stable-diffusion.cpp' }
  Invoke-CMakeBuild $bdir @('sd')
  $out = Join-Path (Join-Path (Join-Path (Join-Path $OUT $arch) $OS_ID) $device) 'stable-diffusion.cpp'
  Copy-Binary $bdir 'sd' $out
}
$arch = Resolve-Arch
$devs = Resolve-Devices $Devices
if ($Projects -eq 'all') { $projs = @('llama','whisper','sd') } else { $projs = $Projects.Split(',') }
Write-Host "==> OS=$OS_ID ARCH=$arch DEVICES=$($devs -join ',') PROJECTS=$($projs -join ',')"

foreach ($d in $devs) {
  foreach ($p in $projs) {
    Write-Host "--- Building $p [$d] ---"
    switch ($p.Trim()) {
      'llama'   { Build-Llama   $d $arch }
      'whisper' { Build-Whisper $d $arch }
      'sd'      { Build-SD      $d $arch }
      default   { throw "Unknown project: $p" }
    }
  }
}

Write-Host "Done. Artifacts under: $OUT\$arch\$OS_ID"






