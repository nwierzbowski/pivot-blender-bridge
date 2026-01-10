# Blender-side Cython modules (bpy/marshalling). IPC SDK is built separately in elbo_sdk.

# Load common configuration
include(${CMAKE_CURRENT_SOURCE_DIR}/../pivot-cmake-common/cmake/PivotCommon.cmake)

find_package(Python3 COMPONENTS Interpreter Development.Module NumPy REQUIRED)
find_program(CYTHON_EXECUTABLE cython REQUIRED)

set(CYTHON_MODULE_SOURCES
    operators/standardize.pyx
    shared/classification.pyx
    shared/collection_manager.pyx
    shared/edition_utils.pyx
    shared/engine_state.pyx
    shared/group_manager.pyx
    shared/selection_utils.pyx
    shared/shm_utils.pyx
    shared/surface_manager.pyx
)

set(PIVOT_WHEEL_PKG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native")
set(PIVOT_WHEEL_OUTPUT_DIR "${PROJECT_SOURCE_DIR}/dist/wheels/${PIVOT_PLATFORM_ID}/${PIVOT_EDITION}")

file(MAKE_DIRECTORY "${PIVOT_WHEEL_PKG_DIR}")
file(MAKE_DIRECTORY "${PIVOT_WHEEL_OUTPUT_DIR}")

set(EDITION_FLAGS_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/edition_flags.pxi.in")
set(EDITION_FLAGS_FILE "${CMAKE_CURRENT_BINARY_DIR}/edition_flags.pxi")
if(EXISTS "${EDITION_FLAGS_TEMPLATE}")
    if(PIVOT_EDITION STREQUAL "PRO")
        set(PIVOT_EDITION_PRO_DEF 1)
        set(PIVOT_EDITION_STANDARD_DEF 0)
    else()
        set(PIVOT_EDITION_PRO_DEF 0)
        set(PIVOT_EDITION_STANDARD_DEF 1)
    endif()
    configure_file("${EDITION_FLAGS_TEMPLATE}" "${EDITION_FLAGS_FILE}" @ONLY)
endif()

set(_pivot_edition_defines)
if(PIVOT_EDITION STREQUAL "PRO")
    list(APPEND _pivot_edition_defines PIVOT_EDITION_PRO)
else()
    list(APPEND _pivot_edition_defines PIVOT_EDITION_STANDARD)
endif()
list(APPEND _pivot_edition_defines PIVOT_EDITION_NAME="${PIVOT_EDITION}")

set(_cython_common_includes
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/.."
    ${Python3_INCLUDE_DIRS}
)

# Detect pivot-core headers so generated C++ can include classification.h.
set(_pivot_core_include_candidates
    "${CMAKE_CURRENT_SOURCE_DIR}/../../elbo-sdk/pivot-core"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../core"
)
foreach(_cand IN LISTS _pivot_core_include_candidates)
    if(EXISTS "${_cand}/classification.h")
        list(APPEND _cython_common_includes "${_cand}")
        break()
    endif()
endforeach()
if(EXISTS "${EDITION_FLAGS_FILE}")
    list(APPEND _cython_common_includes "${CMAKE_CURRENT_BINARY_DIR}")
endif()
list(REMOVE_DUPLICATES _cython_common_includes)

set(_pivot_all_modules)
foreach(mod_src IN LISTS CYTHON_MODULE_SOURCES)
    get_filename_component(mod "${mod_src}" NAME_WE)
    set(SRC "${CMAKE_CURRENT_SOURCE_DIR}/${mod_src}")
    set(OUT "${CMAKE_CURRENT_BINARY_DIR}/${mod}.cpp")

    set(_cython_deps "${SRC}")
    set(PXD_FILE "${CMAKE_CURRENT_SOURCE_DIR}/${mod}.pxd")
    if(EXISTS "${PXD_FILE}")
        list(APPEND _cython_deps "${PXD_FILE}")
    endif()
    if(EXISTS "${EDITION_FLAGS_FILE}")
        list(APPEND _cython_deps "${EDITION_FLAGS_FILE}")
    endif()

    set(_cython_command "${CYTHON_EXECUTABLE}" --cplus)
    foreach(_inc_dir IN LISTS _cython_common_includes)
        list(APPEND _cython_command -I "${_inc_dir}")
    endforeach()
    list(APPEND _cython_command -o "${OUT}" "${SRC}")

    add_custom_command(
        OUTPUT "${OUT}"
        COMMAND ${_cython_command}
        DEPENDS ${_cython_deps}
        COMMENT "Cythonizing ${SRC}"
    )

    add_library(${mod} MODULE "${OUT}")
    list(APPEND _pivot_all_modules ${mod})

    set_target_properties(${mod} PROPERTIES PREFIX "")
    if(WIN32)
        set_target_properties(${mod} PROPERTIES SUFFIX ".pyd")
    endif()

    target_link_libraries(${mod} PRIVATE Python3::Module)
    if(CMAKE_SYSTEM_NAME MATCHES "Linux")
        target_link_libraries(${mod} PRIVATE rt)
    endif()

    target_include_directories(${mod} PRIVATE ${Python3_INCLUDE_DIRS})
    if(Python3_NumPy_INCLUDE_DIRS)
        target_include_directories(${mod} PRIVATE ${Python3_NumPy_INCLUDE_DIRS})
    endif()

    foreach(def IN LISTS _pivot_edition_defines)
        target_compile_definitions(${mod} PRIVATE ${def})
    endforeach()

    foreach(_inc_dir IN LISTS _cython_common_includes)
        target_include_directories(${mod} PRIVATE "${_inc_dir}")
    endforeach()

    set_target_properties(${mod} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${PIVOT_WHEEL_PKG_DIR}")
endforeach()

add_custom_target(pivot_wheel ALL
    COMMAND ${Python3_EXECUTABLE} "${PROJECT_SOURCE_DIR}/build_wheel.py" --output-dir "${PIVOT_WHEEL_OUTPUT_DIR}"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    COMMENT "Building pivot wheel"
    DEPENDS ${_pivot_all_modules}
)
