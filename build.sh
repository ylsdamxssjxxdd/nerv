#!/usr/bin/env bash
set -euo pipefail

# EVA backend build script (Linux/Unix). Builds CPU and Vulkan by default; CUDA/OpenCL optional.
# Artifacts are placed into EVA_BACKEND/<arch>/<os>/<device>/<project>/
# NOTE: This script does NOT clone repositories. Prepare sources yourself.

# Defaults
PROJECTS="all"       # all|llama|whisper|sd (stable-diffusion)
DEVICES="auto"       # auto|cpu|vulkan|cuda|opencl|all (comma-separated allowed)
JOBS=""              # empty => cmake default; else e.g. -j 8
CLEAN=0
ROOT_DIR="$(pwd)"
EXTERN_DIR="$ROOT_DIR/external"
BUILD_DIR="$ROOT_DIR/build"
OUT_DIR="$ROOT_DIR/EVA_BACKEND"

# Optional source path overrides (env or CLI)
LLAMA_SRC_CLI="";   : "${LLAMA_SRC:=}"
WHISPER_SRC_CLI=""; : "${WHISPER_SRC:=}"
SD_SRC_CLI="";      : "${SD_SRC:=}"

# Pinned refs (only checked and warned; no automatic checkout)
LLAMA_EXPECT_REF="b6746"
WHISPER_EXPECT_TAG="v1.8.1"
SD_EXPECT_REF="0585e2609d26fc73cde0dd963127ae585ca62d49"

usage() {
  echo "Usage: $0 [-p projects] [-d devices] [-j jobs] [--clean] [--llama-src PATH] [--whisper-src PATH] [--sd-src PATH]"
  echo "  -p, --projects  all|llama|whisper|sd (comma-separated)"
  echo "  -d, --devices   auto|cpu|vulkan|cuda|opencl|all (comma-separated)"
  echo "  -j, --jobs      parallel build jobs (passed to cmake --build --parallel)"
  echo "      --clean     remove prior build trees for selected projects/devices"
  echo "      --llama-src PATH     explicit llama.cpp source dir"
  echo "      --whisper-src PATH   explicit whisper.cpp source dir"
  echo "      --sd-src PATH        explicit stable-diffusion.cpp source dir"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--projects) PROJECTS="$2"; shift 2;;
      -d|--devices)  DEVICES="$2"; shift 2;;
      -j|--jobs)     JOBS="$2"; shift 2;;
      --clean)       CLEAN=1; shift;;
      --llama-src)   LLAMA_SRC_CLI="$2"; shift 2;;
      --whisper-src) WHISPER_SRC_CLI="$2"; shift 2;;
      --sd-src)      SD_SRC_CLI="$2"; shift 2;;
      -h|--help)     usage; exit 0;;
      *) echo "Unknown arg: $1"; usage; exit 1;;
    esac
  done
}

os_id() {
  local u; u=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$u" in
    linux*) echo linux;;
    darwin*) echo linux;; # normalized as linux per layout spec
    msys*|mingw*|cygwin*) echo win;;
    *) echo linux;;
  esac
}

arch_id() {
  local m; m=$(uname -m)
  case "$m" in
    x86_64|amd64) echo x86_64;;
    i386|i686) echo x86_32;;
    aarch64) echo arm64;;
    armv7l|armv7|arm) echo arm32;;
    *) echo x86_64;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# Device detection
can_vulkan() {
  if [[ -n "${VULKAN_SDK:-}" ]]; then return 0; fi
  if have vulkaninfo; then return 0; fi
  if have glslc; then return 0; fi
  if pkg-config --exists vulkan 2>/dev/null; then return 0; fi
  return 1
}

can_cuda() {
  if have nvcc; then return 0; fi
  if [[ -d /usr/local/cuda ]]; then return 0; fi
  if have nvidia-smi; then return 0; fi
  return 1
}

can_opencl() {
  if pkg-config --exists OpenCL 2>/dev/null; then return 0; fi
  if have clinfo; then return 0; fi
  return 1
}

resolve_devices() {
  local req="$DEVICES"; IFS=',' read -r -a arr <<< "$req"
  local out=()
  if [[ "${#arr[@]}" -eq 1 ]]; then
    case "${arr[0]}" in
      auto)
        out+=(cpu)
        if can_vulkan; then out+=(vulkan); fi
        ;;
      all)
        out=(cpu)
        if can_vulkan; then out+=(vulkan); fi
        if can_cuda; then out+=(cuda); fi
        if can_opencl; then out+=(opencl); fi
        ;;
      *) out=("${arr[@]}");;
    esac
  else
    out=("${arr[@]}")
  fi
  # de-dup
  local seen="" d uniq=()
  for d in "${out[@]}"; do
    if [[ ",$seen," != *",$d,"* ]]; then uniq+=("$d"); seen+="$d,"; fi
  done
  echo "${uniq[*]}"
}

resolve_src_dir() {
  # $1=name (llama|whisper|sd), $2=cliOverride, $3=envVarName
  local name="$1" cli="$2" envname="$3"
  local val=""
  if [[ -n "$cli" ]]; then echo "$cli"; return 0; fi
  eval "val=\${$envname:-}"
  if [[ -n "$val" ]]; then echo "$val"; return 0; fi
  local cand
  case "$name" in
    llama)
      for cand in "$ROOT_DIR/llama.cpp" "$EXTERN_DIR/llama.cpp"; do
        if [[ -f "$cand/CMakeLists.txt" ]]; then echo "$cand"; return 0; fi
      done;;
    whisper)
      for cand in "$ROOT_DIR/whisper.cpp" "$EXTERN_DIR/whisper.cpp"; do
        if [[ -f "$cand/CMakeLists.txt" ]]; then echo "$cand"; return 0; fi
      done;;
    sd)
      for cand in "$ROOT_DIR/stable-diffusion.cpp" "$EXTERN_DIR/stable-diffusion.cpp"; do
        if [[ -f "$cand/CMakeLists.txt" ]]; then echo "$cand"; return 0; fi
      done;;
  esac
  echo ""
}

show_version_note() {
  # $1=label, $2=path, $3=expectRef (short) or empty, $4=expectTag or empty
  local label="$1" path="$2" expectRef="$3" expectTag="$4"
  if [[ -d "$path/.git" ]] && have git; then
    local head tag
    head=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)
    tag=$(git -C "$path" describe --tags --exact-match 2>/dev/null || true)
    local want="" have_ref="${tag:-$head}"
    if [[ -n "$expectTag" ]]; then
      if [[ "$tag" == "$expectTag" ]]; then want="(matches $expectTag)"; else want="(want $expectTag, have $have_ref)"; fi
    elif [[ -n "$expectRef" ]]; then
      if [[ "$head" == "$expectRef"* ]]; then want="(matches $expectRef)"; else want="(want $expectRef, have $have_ref)"; fi
    fi
    echo "[$label] $path ref=$have_ref $want"
  else
    echo "[$label] $path (not a git repo or git not available)"
  fi
}

# Build helpers
cmake_gen() {
  if have ninja; then echo "-G Ninja"; else echo ""; fi
}

cmake_jobs_flag() {
  if [[ -n "$JOBS" ]]; then echo "--parallel $JOBS"; else echo ""; fi
}

copy_bin() {
  local src_dir="$1" tgt_name="$2" out_dir="$3" exe_suf="$4"
  local cand
  mkdir -p "$out_dir"
  # Common candidate locations
  for cand in \
    "$src_dir/$tgt_name$exe_suf" \
    "$src_dir/bin/$tgt_name$exe_suf" \
    "$src_dir/Release/$tgt_name$exe_suf" \
    "$src_dir/bin/Release/$tgt_name$exe_suf" \
    "$src_dir/$tgt_name" \
    "$src_dir/bin/$tgt_name"
  do
    if [[ -f "$cand" ]]; then
      cp -f "$cand" "$out_dir/"
      echo "Copied $(basename "$cand") -> $out_dir"
      return 0
    fi
  done
  echo "[warn] Could not locate built binary '$tgt_name$exe_suf' under $src_dir" >&2
  return 1
}

build_llama() {
  local device="$1" os="$2" arch="$3" exe_suf="$4"
  local src
  src="$(resolve_src_dir llama "$LLAMA_SRC_CLI" LLAMA_SRC)"
  if [[ -z "$src" ]]; then
    echo "[error] llama.cpp source not found. Provide --llama-src or set LLAMA_SRC or place repo at ./llama.cpp or ./external/llama.cpp" >&2
    exit 2
  fi
  show_version_note "llama.cpp" "$src" "$LLAMA_EXPECT_REF" ""
  local bdir="$BUILD_DIR/llama.cpp/$device"
  if [[ $CLEAN -eq 1 ]]; then rm -rf "$bdir"; fi
  mkdir -p "$bdir"
  local vflag="-DGGML_VULKAN=OFF" cuflag="-DGGML_CUDA=OFF" ocflag="-DGGML_OPENCL=OFF"
  local NATIVE_EXTRA=""
  case "$device" in
    vulkan) vflag="-DGGML_VULKAN=ON" ;;
    cuda)   cuflag="-DGGML_CUDA=ON"; NATIVE_EXTRA="-DGGML_NATIVE=OFF" ;;
    opencl) ocflag="-DGGML_OPENCL=ON" ;;
  esac
  cmake -S "$src" -B "$bdir" $(cmake_gen) \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_BUILD_SERVER=ON \
    $vflag $cuflag $ocflag $NATIVE_EXTRA -DCMAKE_BUILD_TYPE=Release
  # Determine available targets and build only those
  local help_out
  help_out=$(cmake --build "$bdir" --config Release --target help 2>/dev/null || true)
  local targets=()
  for t in llama-server llama-quantize llama-tts; do
    if echo "$help_out" | grep -q "$t"; then targets+=("$t"); fi
  done
  if [[ "${#targets[@]}" -eq 0 ]]; then
    echo "[warn] No expected llama.cpp targets found; building default ALL" >&2
    cmake --build "$bdir" $(cmake_jobs_flag) --config Release
  else
    cmake --build "$bdir" $(cmake_jobs_flag) --config Release --target ${targets[@]}
  fi
  local out="$OUT_DIR/$arch/$os/$device/llama.cpp"
  copy_bin "$bdir" llama-server "$out" "$exe_suf" || true
  copy_bin "$bdir" llama-quantize "$out" "$exe_suf" || true
  copy_bin "$bdir" llama-tts "$out" "$exe_suf" || true
}

build_whisper() {
  local device="$1" os="$2" arch="$3" exe_suf="$4"
  local src
  src="$(resolve_src_dir whisper "$WHISPER_SRC_CLI" WHISPER_SRC)"
  if [[ -z "$src" ]]; then
    echo "[error] whisper.cpp source not found. Provide --whisper-src or set WHISPER_SRC or place repo at ./whisper.cpp or ./external/whisper.cpp" >&2
    exit 2
  fi
  show_version_note "whisper.cpp" "$src" "" "$WHISPER_EXPECT_TAG"
  local bdir="$BUILD_DIR/whisper.cpp/$device"
  if [[ $CLEAN -eq 1 ]]; then rm -rf "$bdir"; fi
  mkdir -p "$bdir"
  local vflag="-DGGML_VULKAN=OFF" cuflag="-DGGML_CUDA=OFF" ocflag="-DGGML_OPENCL=OFF"
  local NATIVE_EXTRA=""
  case "$device" in
    vulkan) vflag="-DGGML_VULKAN=ON" ;;
    cuda)   cuflag="-DGGML_CUDA=ON"; NATIVE_EXTRA="-DGGML_NATIVE=OFF" ;;
    opencl) ocflag="-DGGML_OPENCL=ON" ;;
  esac
  cmake -S "$src" -B "$bdir" $(cmake_gen) \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON \
    $vflag $cuflag $ocflag $NATIVE_EXTRA -DCMAKE_BUILD_TYPE=Release
  cmake --build "$bdir" $(cmake_jobs_flag) --config Release --target whisper-cli
  local out="$OUT_DIR/$arch/$os/$device/whisper.cpp"
  copy_bin "$bdir" whisper-cli "$out" "$exe_suf" || true
}

build_sd() {
  local device="$1" os="$2" arch="$3" exe_suf="$4"
  local src
  src="$(resolve_src_dir sd "$SD_SRC_CLI" SD_SRC)"
  if [[ -z "$src" ]]; then
    echo "[error] stable-diffusion.cpp source not found. Provide --sd-src or set SD_SRC or place repo at ./stable-diffusion.cpp or ./external/stable-diffusion.cpp" >&2
    exit 2
  fi
  show_version_note "stable-diffusion.cpp" "$src" "$SD_EXPECT_REF" ""
  local bdir="$BUILD_DIR/stable-diffusion.cpp/$device"
  if [[ $CLEAN -eq 1 ]]; then rm -rf "$bdir"; fi
  mkdir -p "$bdir"
  local vflag="-DGGML_VULKAN=OFF" cuflag="-DGGML_CUDA=OFF" ocflag="-DGGML_OPENCL=OFF"
  local SD_EXTRA=""
  local NATIVE_EXTRA=""
  case "$device" in
    vulkan) vflag="-DGGML_VULKAN=ON"; SD_EXTRA="-DSD_VULKAN=ON";;
    cuda)   cuflag="-DGGML_CUDA=ON";   SD_EXTRA="-DSD_CUDA=ON"; NATIVE_EXTRA="-DGGML_NATIVE=OFF";;
    opencl) ocflag="-DGGML_OPENCL=ON"; SD_EXTRA="-DSD_OPENCL=ON";;
  esac
  cmake -S "$src" -B "$bdir" $(cmake_gen) \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    $vflag $cuflag $ocflag $SD_EXTRA $NATIVE_EXTRA -DCMAKE_BUILD_TYPE=Release
  cmake --build "$bdir" $(cmake_jobs_flag) --config Release --target sd
  local out="$OUT_DIR/$arch/$os/$device/stable-diffusion.cpp"
  copy_bin "$bdir" sd "$out" "$exe_suf" || true
}

main() {
  parse_args "$@"
  local OS=$(os_id) ARCH=$(arch_id)
  local EXE_SUF=""; if [[ "$OS" == "win" ]]; then EXE_SUF=".exe"; fi

  IFS=' ' read -r -a DEV_ARR <<< "$(resolve_devices)"

  # Resolve project list
  local PROJ_ARR=()
  if [[ "$PROJECTS" == "all" ]]; then
    PROJ_ARR=(llama whisper sd)
  else
    IFS=',' read -r -a PROJ_ARR <<< "$PROJECTS"
  fi

  echo "==> OS=$OS ARCH=$ARCH DEVICES=${DEV_ARR[*]} PROJECTS=${PROJ_ARR[*]}"

  for dev in "${DEV_ARR[@]}"; do
    for proj in "${PROJ_ARR[@]}"; do
      echo "--- Building $proj [$dev] ---"
      case "$proj" in
        llama)   build_llama   "$dev" "$OS" "$ARCH" "$EXE_SUF";;
        whisper) build_whisper "$dev" "$OS" "$ARCH" "$EXE_SUF";;
        sd)      build_sd      "$dev" "$OS" "$ARCH" "$EXE_SUF";;
        *) echo "Unknown project: $proj"; exit 1;;
      esac
    done
  done

  echo "Done. Artifacts under: $OUT_DIR/$ARCH/$OS"
}

main "$@"


