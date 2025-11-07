# Core subproject for shared headers

add_library(core INTERFACE)
target_include_directories(core INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})
if(MSVC)
	target_compile_definitions(core INTERFACE BOOST_ALL_NO_LIB BOOST_INTERPROCESS_NO_LIB)
endif()
