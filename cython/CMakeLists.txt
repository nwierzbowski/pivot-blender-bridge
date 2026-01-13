# Copyright (C) 2025 Nicholas Wierzbowski / Elbo Studio
# This file is part of the Pivot Bridge for Blender.

# execute_process(
#     COMMAND "${Python_EXECUTABLE}" -c "import cython_cmake, os; print(os.path.join(os.path.dirname(cython_cmake.__file__), 'cmake'))"
#     OUTPUT_VARIABLE CYTHON_CMAKE_DIR
#     OUTPUT_STRIP_TRAILING_WHITESPACE
# )

# # Add that directory to your search path
# list(APPEND CMAKE_MODULE_PATH "${CYTHON_CMAKE_DIR}")

#Find and add cython_cmake to module path
if (PIVOT_DEV)
execute_process(
    COMMAND "${Python_EXECUTABLE}" -c "import cython_cmake, os; print(os.path.join(os.path.dirname(cython_cmake.__file__), 'cmake'))"
    OUTPUT_VARIABLE CYTHON_CMAKE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Add that directory to your search path
list(APPEND CMAKE_MODULE_PATH "${CYTHON_CMAKE_DIR}")
endif()

# Find python for Cython module
find_package(Python COMPONENTS Interpreter Development.Module NumPy REQUIRED)
find_package(Cython REQUIRED MODULE)
include(UseCython)

set(BLENDER_BRIDGE_STAGING_DIR "${CMAKE_CURRENT_BINARY_DIR}/staging/blender_bridge")

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../native/__init__.py"
    "${BLENDER_BRIDGE_STAGING_DIR}/__init__.py"
    COPYONLY
)

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

set(CYTHON_MODULE_SOURCES
    standardize
    classification
    collection_manager
    edition_utils
    engine_state
    group_manager
    selection_utils
    shm_utils
    surface_manager
)

set(_blender_bridge_targets)
foreach(_module IN LISTS CYTHON_MODULE_SOURCES)
    set(_module_src "${CMAKE_CURRENT_SOURCE_DIR}/${_module}.pyx")

    cython_transpile("${_module_src}" LANGUAGE CXX
        CYTHON_ARGS "-I${CMAKE_CURRENT_BINARY_DIR}"
        OUTPUT_VARIABLE _generated_c
    )

    python_add_library(${_module} MODULE WITH_SOABI ${_generated_c})
    set_target_properties(${_module} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${BLENDER_BRIDGE_STAGING_DIR}"
        LINKER_LANGUAGE CXX
    )
    pivot_common_set_edition_defines(${_module} PIVOT_EDITION)
    target_include_directories(${_module} PRIVATE ${pivot-core_SOURCE_DIR})
    target_link_libraries(${_module} PRIVATE Python::Module Python::NumPy pivot_common::base_cython)

    install(TARGETS ${_module} LIBRARY DESTINATION pivot_lib)
    list(APPEND _blender_bridge_targets ${_module})
endforeach()


install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../native/__init__.py" DESTINATION pivot_lib)

add_custom_target(blender_bridge_cython
    DEPENDS ${_blender_bridge_targets}
)

# Symlink to Blender site-packages for development
pivot_common_cython_add_blender_symlink(
    TARGET_NAME blender_bridge_cython
    SOURCE_PATH "${BLENDER_BRIDGE_STAGING_DIR}"
    PACKAGE_NAME pivot_lib
    BLENDER_SITE_PACKAGES "${BLENDER_SITE_PACKAGES}"
)

