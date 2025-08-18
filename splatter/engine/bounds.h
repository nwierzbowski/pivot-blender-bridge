#pragma once

#include "util.h"

#include <cstdint>

void align_min_bounds(const Vec3* verts, uint32_t vertCount, Vec3* out_rot, Vec3* out_trans);
