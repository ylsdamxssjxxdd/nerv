# EvaPaths.cmake - compose output folders and helper macros
include_guard(GLOBAL)

if (NOT DEFINED EVA_BACKEND_ROOT)
    set(EVA_BACKEND_ROOT "${CMAKE_SOURCE_DIR}/EVA_BACKEND")
endif()

function(eva_backend_dir OUT_VAR DEVICE PROJECT)
    # Compose EVA_BACKEND/<arch>/<os>/<device>/<project>
    set(_dir "${EVA_BACKEND_ROOT}/${EVA_ARCH}/${EVA_OS}/${DEVICE}/${PROJECT}")
    file(MAKE_DIRECTORY "${_dir}")
    set(${OUT_VAR} "${_dir}" PARENT_SCOPE)
endfunction()
