#pragma once

#include "share/vec.h"

void standardize_object_transform(const Vec3 *verts, uint32_t vertCount, const uVec2i *edges, uint32_t edgeCount, Vec3 *out_rot, Vec3 *out_trans);

void prepare_object_batch(const Vec3 *verts_flat, const uVec2i *edges_flat, const uint32_t *vert_counts, const uint32_t *edge_counts, uint32_t num_objects, Vec3 *out_rots, Vec3 *out_trans);