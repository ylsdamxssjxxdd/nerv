# CopyOutputs.cmake - invoked with -Dsrc_bin= -Ddst_dir= -Dtargets="a;b;c" -Dexe_sfx=
# It copies any existing target from common locations to dst_dir.

if (NOT DEFINED src_bin)
    message(FATAL_ERROR "src_bin not set")
endif()
if (NOT DEFINED dst_dir)
    message(FATAL_ERROR "dst_dir not set")
endif()
if (NOT DEFINED targets)
    message(FATAL_ERROR "targets not set")
endif()
if (NOT DEFINED exe_sfx)
    set(exe_sfx "")
endif()

file(MAKE_DIRECTORY "${dst_dir}")
set(_copied 0)
foreach(t IN LISTS targets)
    # Candidate locations
    set(cands
        "${src_bin}/${t}${exe_sfx}"
        "${src_bin}/Release/${t}${exe_sfx}"
        "${src_bin}/RelWithDebInfo/${t}${exe_sfx}"
        "${src_bin}/MinSizeRel/${t}${exe_sfx}"
        "${src_bin}/Debug/${t}${exe_sfx}"
    )
    set(found "")
    foreach(p IN LISTS cands)
        if (EXISTS "${p}")
            set(found "${p}")
            break()
        endif()
    endforeach()
    if (found)
        message(STATUS "Copying ${found} -> ${dst_dir}")
        file(COPY "${found}" DESTINATION "${dst_dir}")
        math(EXPR _copied "${_copied}+1")
    else()
        message(WARNING "Target not found: ${t}${exe_sfx} in ${src_bin}")
    endif()
endforeach()

if (NOT _copied)
    message(FATAL_ERROR "No outputs copied to ${dst_dir}. Build may have failed or targets list wrong.")
endif()