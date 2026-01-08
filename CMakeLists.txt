cmake_minimum_required(VERSION 3.16)

project(blender_bridge LANGUAGES CXX)

# Load shared Pivot configuration when working against the full repo or standalone.
include(${CMAKE_CURRENT_SOURCE_DIR}/pivot-cmake-common/PivotCommon.cmake)

# Blender-side Cython modules (data marshalling + bpy integrations) are built here.
# Platform-independent IPC and shared-memory bindings live in the sibling elbo_sdk project.

option(BUILD_PY_MODULE "Build Blender-side Python (Cython) modules" ON)

if(BUILD_PY_MODULE)
		if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/cython/CMakeLists.txt)
				add_subdirectory(cython)
		endif()
endif()

# Convenience meta-target
if(NOT TARGET dev)
	add_custom_target(dev ALL)
	if(TARGET pivot_wheel)
		add_dependencies(dev pivot_wheel)
	endif()
endif()
