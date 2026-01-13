cmake_minimum_required(VERSION 4.2.1)

include(FetchContent)

FetchContent_Declare(
    pivot-cmake-common
    GIT_REPOSITORY https://github.com/nwierzbowski/pivot-cmake-common.git  # Replace with actual repo URL
    GIT_TAG main  # Replace with appropriate tag or commit
)
FetchContent_MakeAvailable(pivot-cmake-common)

# Load common Pivot configuration
include(${pivot-cmake-common_SOURCE_DIR}/cmake/PivotCommon.cmake)

setup_common_toolchain()



project(blender_bridge LANGUAGES CXX)

setup_common_interfaces()

FetchContent_Declare(
    pivot-core
    GIT_REPOSITORY https://github.com/nwierzbowski/pivot-core.git
    GIT_TAG main
)

FetchContent_MakeAvailable(pivot-core)

option(BUILD_PY_MODULE "Build Blender-side Python (Cython) modules" ON)

if(BUILD_PY_MODULE)
	add_subdirectory(cython)
endif()

# Convenience meta-target
if(NOT TARGET dev)
	add_custom_target(dev ALL)
endif()

if(TARGET blender_bridge_cython)
	add_dependencies(dev blender_bridge_cython)
endif()
