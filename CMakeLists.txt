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
    )

    # Build llama.cpp (server/quantize/tts)
    if (EVA_BUILD_LLAMA)
        set(_ll_src ${CMAKE_SOURCE_DIR}/llama.cpp)
        set(_ll_bin ${CMAKE_BINARY_DIR}/build-llama-${_dev})
        eva_backend_dir(_ll_dst ${_dev} "llama.cpp")

        ExternalProject_Add(llama_${_dev}
            SOURCE_DIR ${_ll_src}
            BINARY_DIR ${_ll_bin}
            INSTALL_DIR ${_ll_dst}
            CMAKE_ARGS
                -DLLAMA_BUILD_TOOLS=ON
                -DLLAMA_BUILD_EXAMPLES=OFF
                -DLLAMA_BUILD_SERVER=ON
                -DLLAMA_CURL=ON
                ${COMMON_GGML_ARGS}
            BUILD_BYPRODUCTS
                ${_ll_bin}/bin/llama-server${EVA_EXE_SUFFIX}
            INSTALL_COMMAND
                ${CMAKE_COMMAND} -E make_directory "${_ll_dst}"
                COMMAND ${CMAKE_COMMAND}
                    -Dsrc_bin=${_ll_bin}/bin
                    -Ddst_dir=${_ll_dst}
                    -Dtargets=llama-server;llama-quantize;llama-tts
                    -Dexe_sfx=${EVA_EXE_SUFFIX}
                    -P ${CMAKE_SOURCE_DIR}/cmake/CopyOutputs.cmake
        )
    endif()

    # Build whisper.cpp (whisper-cli)
    if (EVA_BUILD_WHISPER)
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
    if (EVA_BUILD_SD)
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
