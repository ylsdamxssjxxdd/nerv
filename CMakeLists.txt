cmake_minimum_required(VERSION 3.20)
project(eva-backend-superbuild LANGUAGES C CXX)

include(ExternalProject)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(EvaDetect)
include(EvaPaths)

# User options
option(EVA_BUILD_LLAMA   "Build llama.cpp targets" ON)
option(EVA_BUILD_WHISPER "Build whisper.cpp targets" ON)
option(EVA_BUILD_SD      "Build stable-diffusion.cpp targets" ON)

# Per-project CUDA toggles (default OFF for whisper/sd; llama uses global EVA_BUILD_CUDA)
option(EVA_BUILD_WHISPER_CUDA "Build CUDA variant of whisper.cpp" OFF)
option(EVA_BUILD_SD_CUDA      "Build CUDA variant of stable-diffusion.cpp" OFF)

# Summary of detection
message(STATUS "EVA platform: arch=${EVA_ARCH}, os=${EVA_OS}")
message(STATUS "Detected devices: CUDA=${EVA_HAS_CUDA}, Vulkan=${EVA_HAS_VULKAN}, OpenCL=${EVA_HAS_OPENCL}")
message(STATUS "Build plan: CPU=${EVA_BUILD_CPU}, CUDA=${EVA_BUILD_CUDA}, Vulkan=${EVA_BUILD_VULKAN}, OpenCL=${EVA_BUILD_OPENCL}")

# Helper to add one subproject build per device
function(eva_add_3rdparty_for_device DEVICE)
    string(TOLOWER "${DEVICE}" _dev)

    # Compose per-device ggml options
    set(OPT_GGML_CUDA   OFF)
    set(OPT_GGML_VULKAN OFF)
    set(OPT_GGML_OPENCL OFF)

    set(SD_OPT_CUDA   OFF)
    set(SD_OPT_VULKAN OFF)
    set(SD_OPT_OPENCL OFF)

    if (_dev STREQUAL "cuda")
        set(OPT_GGML_CUDA   ON)
        set(SD_OPT_CUDA     ON)
    elseif(_dev STREQUAL "vulkan")
        set(OPT_GGML_VULKAN ON)
        set(SD_OPT_VULKAN   ON)
    elseif(_dev STREQUAL "opencl")
        set(OPT_GGML_OPENCL ON)
        set(SD_OPT_OPENCL   ON)
    elseif(NOT _dev STREQUAL "cpu")
        message(FATAL_ERROR "Unknown device: ${DEVICE}")
    endif()

    # Common cmake args for ggml-based projects
    set(COMMON_GGML_ARGS
        -DCMAKE_POLICY_DEFAULT_CMP0077=NEW
        -DGGML_CUDA=${OPT_GGML_CUDA}
        -DGGML_VULKAN=${OPT_GGML_VULKAN}
        -DGGML_OPENCL=${OPT_GGML_OPENCL}
        -DGGML_ALL_WARNINGS=OFF
        -DBUILD_SHARED_LIBS=OFF
        -DGGML_STATIC=ON
        -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
        )

        # Only disable GGML_NATIVE for CUDA to support multiple driver/toolkit versions
        if (_dev STREQUAL "cuda")
            list(APPEND COMMON_GGML_ARGS -DGGML_NATIVE=OFF)
        endif()
    # Build llama.cpp (server/quantize/tts)
    if (EVA_BUILD_LLAMA)
        set(_ll_src ${CMAKE_SOURCE_DIR}/llama.cpp)
        set(_ll_bin ${CMAKE_BINARY_DIR}/build-llama-${_dev})
        eva_backend_dir(_ll_dst ${_dev} "llama.cpp")

        # Device-specific copy targets: for CUDA, only copy llama-server
        set(LLAMA_COPY_TARGETS "llama-server;llama-quantize;llama-tts")
        if (${_dev} STREQUAL "cuda")
            set(LLAMA_COPY_TARGETS "llama-server")
        endif()
        # Escape semicolons so -Dtargets remains a single argument in COMMAND (Linux/macOS shells)
        string(REPLACE ";" "\\;" LLAMA_COPY_TARGETS_ESC "${LLAMA_COPY_TARGETS}")
        ExternalProject_Add(llama_${_dev}
            SOURCE_DIR ${_ll_src}
            BINARY_DIR ${_ll_bin}
            INSTALL_DIR ${_ll_dst}
            CMAKE_ARGS
                -DLLAMA_BUILD_TOOLS=ON
                -DLLAMA_BUILD_EXAMPLES=OFF
                -DLLAMA_BUILD_SERVER=ON
                -DLLAMA_CURL=OFF
                ${COMMON_GGML_ARGS}
            BUILD_BYPRODUCTS
                ${_ll_bin}/bin/llama-server${EVA_EXE_SUFFIX}
                ${_ll_bin}/bin/llama-quantize${EVA_EXE_SUFFIX}
                ${_ll_bin}/bin/llama-tts${EVA_EXE_SUFFIX}
            INSTALL_COMMAND
                ${CMAKE_COMMAND} -E make_directory "${_ll_dst}"
                COMMAND ${CMAKE_COMMAND}
                    -Dsrc_bin=${_ll_bin}/bin
                    -Ddst_dir=${_ll_dst}
                    -Dtargets=${LLAMA_COPY_TARGETS_ESC}
                    -Dexe_sfx=${EVA_EXE_SUFFIX}
                    -P ${CMAKE_SOURCE_DIR}/cmake/CopyOutputs.cmake
        )
    endif()

    # Build whisper.cpp (whisper-cli)
    if (EVA_BUILD_WHISPER AND (NOT _dev STREQUAL "cuda" OR EVA_BUILD_WHISPER_CUDA))
        set(_wp_src ${CMAKE_SOURCE_DIR}/whisper.cpp)
        set(_wp_bin ${CMAKE_BINARY_DIR}/build-whisper-${_dev})
        eva_backend_dir(_wp_dst ${_dev} "whisper.cpp")

        ExternalProject_Add(whisper_${_dev}
            SOURCE_DIR ${_wp_src}
            BINARY_DIR ${_wp_bin}
            INSTALL_DIR ${_wp_dst}
            CMAKE_ARGS
                -DWHISPER_BUILD_EXAMPLES=ON
                -DWHISPER_BUILD_SERVER=OFF
                -DWHISPER_CURL=OFF
                ${COMMON_GGML_ARGS}
            BUILD_BYPRODUCTS
                ${_wp_bin}/bin/whisper-cli${EVA_EXE_SUFFIX}
            INSTALL_COMMAND
                ${CMAKE_COMMAND} -E make_directory "${_wp_dst}"
                COMMAND ${CMAKE_COMMAND}
                    -Dsrc_bin=${_wp_bin}/bin
                    -Ddst_dir=${_wp_dst}
                    -Dtargets=whisper-cli
                    -Dexe_sfx=${EVA_EXE_SUFFIX}
                    -P ${CMAKE_SOURCE_DIR}/cmake/CopyOutputs.cmake
        )
    endif()

    # Build stable-diffusion.cpp (sd)
    if (EVA_BUILD_SD AND (NOT _dev STREQUAL "cuda" OR EVA_BUILD_SD_CUDA))
        set(_sd_src ${CMAKE_SOURCE_DIR}/stable-diffusion.cpp)
        set(_sd_bin ${CMAKE_BINARY_DIR}/build-sd-${_dev})
        eva_backend_dir(_sd_dst ${_dev} "stable-diffusion.cpp")

        ExternalProject_Add(sd_${_dev}
            SOURCE_DIR ${_sd_src}
            BINARY_DIR ${_sd_bin}
            INSTALL_DIR ${_sd_dst}
            CMAKE_ARGS
                -DSD_BUILD_EXAMPLES=ON
                -DSD_BUILD_SHARED_LIBS=OFF
                -DSD_CUDA=${SD_OPT_CUDA}
                -DSD_VULKAN=${SD_OPT_VULKAN}
                -DSD_OPENCL=${SD_OPT_OPENCL}
                ${COMMON_GGML_ARGS}
            BUILD_BYPRODUCTS
                ${_sd_bin}/bin/sd${EVA_EXE_SUFFIX}
            INSTALL_COMMAND
                ${CMAKE_COMMAND} -E make_directory "${_sd_dst}"
                COMMAND ${CMAKE_COMMAND}
                    -Dsrc_bin=${_sd_bin}/bin
                    -Ddst_dir=${_sd_dst}
                    -Dtargets=sd
                    -Dexe_sfx=${EVA_EXE_SUFFIX}
                    -P ${CMAKE_SOURCE_DIR}/cmake/CopyOutputs.cmake
        )
    endif()
endfunction()

# Always build CPU
if (EVA_BUILD_CPU)
    eva_add_3rdparty_for_device(cpu)
endif()

if (EVA_BUILD_CUDA AND EVA_HAS_CUDA)
    eva_add_3rdparty_for_device(cuda)
elseif(EVA_BUILD_CUDA AND NOT EVA_HAS_CUDA)
    message(WARNING "Requested CUDA build but CUDA not detected; skipping")
endif()

if (EVA_BUILD_VULKAN AND EVA_HAS_VULKAN)
    eva_add_3rdparty_for_device(vulkan)
elseif(EVA_BUILD_VULKAN AND NOT EVA_HAS_VULKAN)
    message(WARNING "Requested Vulkan build but Vulkan not detected; skipping")
endif()

if (EVA_BUILD_OPENCL AND EVA_HAS_OPENCL)
    eva_add_3rdparty_for_device(opencl)
elseif(EVA_BUILD_OPENCL AND NOT EVA_HAS_OPENCL)
    message(WARNING "Requested OpenCL build but OpenCL not detected; skipping")
endif()

# Convenience target to copy everything again (if needed)
add_custom_target(eva-sync ALL
    COMMAND ${CMAKE_COMMAND} -E echo "EVA backend planned under ${EVA_BACKEND_ROOT}"
)

# Make ALL build depend on all ExternalProject targets
set(_eva_all_deps)
if (EVA_BUILD_LLAMA)
    list(APPEND _eva_all_deps llama_cpu)
    if (EVA_BUILD_CUDA AND EVA_HAS_CUDA)
        list(APPEND _eva_all_deps llama_cuda)
    endif()
    if (EVA_BUILD_VULKAN AND EVA_HAS_VULKAN)
        list(APPEND _eva_all_deps llama_vulkan)
    endif()
    if (EVA_BUILD_OPENCL AND EVA_HAS_OPENCL)
        list(APPEND _eva_all_deps llama_opencl)
    endif()
endif()
if (EVA_BUILD_WHISPER)
    list(APPEND _eva_all_deps whisper_cpu)
    if (EVA_BUILD_CUDA AND EVA_HAS_CUDA)
        if (EVA_BUILD_WHISPER_CUDA)
            list(APPEND _eva_all_deps whisper_cuda)
        endif()
    endif()
    if (EVA_BUILD_VULKAN AND EVA_HAS_VULKAN)
        list(APPEND _eva_all_deps whisper_vulkan)
    endif()
    if (EVA_BUILD_OPENCL AND EVA_HAS_OPENCL)
        list(APPEND _eva_all_deps whisper_opencl)
    endif()
endif()
if (EVA_BUILD_SD)
    list(APPEND _eva_all_deps sd_cpu)
    if (EVA_BUILD_CUDA AND EVA_HAS_CUDA)
        if (EVA_BUILD_SD_CUDA)
            list(APPEND _eva_all_deps sd_cuda)
        endif()
    endif()
    if (EVA_BUILD_VULKAN AND EVA_HAS_VULKAN)
        list(APPEND _eva_all_deps sd_vulkan)
    endif()
    if (EVA_BUILD_OPENCL AND EVA_HAS_OPENCL)
        list(APPEND _eva_all_deps sd_opencl)
    endif()
endif()
if (_eva_all_deps)
    add_dependencies(eva-sync ${_eva_all_deps})
endif()

get_property(_eva_targets GLOBAL PROPERTY EVA_EXTERNAL_TARGETS)
if (_eva_targets)
    add_dependencies(eva-sync ${_eva_targets})
endif()