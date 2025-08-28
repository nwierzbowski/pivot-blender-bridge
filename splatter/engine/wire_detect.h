#pragma once

#include "vec.h"
#include "voxel.h"

#include <vector>
#include <unordered_map>

void select_wire_verts(
    uint32_t vertCount,
    const std::vector<std::vector<uint32_t>> &adj_verts,
    const std::vector<VoxelKey> &voxel_guesses,
    VoxelMap &voxel_map,
    std::vector<bool> &mask);