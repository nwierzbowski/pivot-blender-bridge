# Python (Cython) module subproject

find_package(Python3 COMPONENTS Interpreter Development.Module NumPy REQUIRED)
find_program(CYTHON_EXECUTABLE cython REQUIRED)

set(CYTHON_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/bridge.pyx)
set(CYTHON_GENERATED_CPP ${CMAKE_CURRENT_BINARY_DIR}/bridge.cpp)

add_custom_command(
    OUTPUT ${CYTHON_GENERATED_CPP}
    # Generate annotated HTML (-a) alongside the C++ source for performance insight
    COMMAND ${CYTHON_EXECUTABLE} --cplus -a -I ${CMAKE_CURRENT_SOURCE_DIR}/.. -o ${CYTHON_GENERATED_CPP} ${CYTHON_SOURCE}
    # Declare the HTML as a byproduct so build systems (e.g. Ninja) know about it
    BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/bridge.html
    DEPENDS ${CYTHON_SOURCE}
    COMMENT "Cythonizing ${CYTHON_SOURCE} with HTML annotations"
)

add_library(bridge MODULE ${CYTHON_GENERATED_CPP})
set_target_properties(bridge PROPERTIES PREFIX "")

# Correct platform-specific suffix is handled by Python3::Module on most platforms
if(WIN32)
    set_target_properties(bridge PROPERTIES SUFFIX ".pyd")
endif()

target_link_libraries(bridge PRIVATE Python3::Module)

# Numpy headers
if(Python3_NumPy_INCLUDE_DIRS)
    target_include_directories(bridge PRIVATE ${Python3_NumPy_INCLUDE_DIRS})
endif()

# Include engine src for classification.h
target_include_directories(bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../core)

# Link core library
target_link_libraries(bridge PRIVATE core)

# Output extension into the package directory so Python can import it
set_target_properties(bridge PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../splatter")
