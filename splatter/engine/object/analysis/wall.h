#pragma once

#include "object/computation/b_box.h"
#include "share/vec.h"


bool is_wall(std::vector<Vec3> &verts, BoundingBox3D full_box, uint8_t &front_axis_out);