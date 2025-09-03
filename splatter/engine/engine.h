#pragma once

#include "share/vec.h"

void standardize_object_transform(const Vec3 *verts, uint32_t vertCount, const uVec2i *edges, uint32_t edgeCount, Vec3 *out_rot, Vec3 *out_trans);
