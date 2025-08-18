#include "chull.h"

#include "util.h"

#include <iostream>
#include <cstdint>


void say_hello_from_cpp() {
    std::cout << "Hello from the C++ Engine! Recomp" << std::endl;
}

void convex_hull_2D(const Vec3* verts, uint32_t vertCount) {
    std::cout << "verts size is: " << sizeof(verts) << std::endl;
    std::cout << "vertCount is: " << vertCount << std::endl;
}