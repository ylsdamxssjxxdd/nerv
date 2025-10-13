# EvaDetect.cmake - detect OS, arch, and available devices
include_guard(GLOBAL)

# Compute EVA_OS string
if (CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(EVA_OS "win")
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(EVA_OS "linux")
else()
    set(EVA_OS "unknown")
endif()

# Compute EVA_ARCH string (x86_64/x86_32/arm64/arm32)
set(_arch "${CMAKE_SYSTEM_PROCESSOR}")
string(TOLOWER "${_arch}" _arch_l)

if (_arch_l MATCHES "amd64|x86_64")
    if (CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(EVA_ARCH "x86_64")
    else()
        set(EVA_ARCH "x86_32")
    endif()
elseif (_arch_l MATCHES "i[3-6]86|x86")
    set(EVA_ARCH "x86_32")
elseif (_arch_l MATCHES "arm64|aarch64")
    set(EVA_ARCH "arm64")
elseif (_arch_l MATCHES "arm|armv7|armv8")
    set(EVA_ARCH "arm32")
else()
    # default conservatively
    if (CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(EVA_ARCH "x86_64")
    else()
        set(EVA_ARCH "x86_32")
    endif()
endif()

# Device detection (best-effort)
include(CheckCXXSourceCompiles)

# CUDA
set(EVA_HAS_CUDA OFF)
find_package(CUDAToolkit QUIET)
if (CUDAToolkit_FOUND)
    set(EVA_HAS_CUDA ON)
endif()

# Vulkan
set(EVA_HAS_VULKAN OFF)
find_package(Vulkan QUIET)
if (Vulkan_FOUND)
    set(EVA_HAS_VULKAN ON)
endif()

# OpenCL
set(EVA_HAS_OPENCL OFF)
find_package(OpenCL QUIET)
if (OpenCL_FOUND)
    set(EVA_HAS_OPENCL ON)
endif()

# 32-bit toolchains generally cannot use CUDA/Vulkan/OpenCL backends on Windows
if (CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(EVA_HAS_CUDA OFF)
    set(EVA_HAS_VULKAN OFF)
    set(EVA_HAS_OPENCL OFF)
endif()

# Build toggles (auto-detected by default, can be overridden by user)
option(EVA_BUILD_CPU    "Build CPU variants"                           ON)
option(EVA_BUILD_CUDA   "Build CUDA variants (OFF by default)"             OFF)
option(EVA_BUILD_VULKAN "Build Vulkan variants if available"           ${EVA_HAS_VULKAN})
option(EVA_BUILD_OPENCL "Build OpenCL variants (OFF by default)"           OFF)

# Resolve exe suffix once
if (WIN32)
    set(EVA_EXE_SUFFIX ".exe")
else()
    set(EVA_EXE_SUFFIX "")
endif()
