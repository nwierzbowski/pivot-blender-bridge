#include "engine.h"
#include "vec.h"
#include "voxel.h"
#include "wire_detect.h"
#include "geo2d.h"

#include <vector>
#include <chrono>
#include <iostream>
#include <algorithm>

std::vector<std::vector<uint32_t>> build_adj_vertices(const uVec2i *edges, uint32_t edgeCount, uint32_t vertCount)
{
    std::vector<std::vector<uint32_t>> adj_verts(vertCount);
    if (!edges || edgeCount == 0)
        return adj_verts;

    // --- Reserve memory for each adjacency list ---
    std::vector<uint32_t> degrees(vertCount, 0);
    for (uint32_t i = 0; i < edgeCount; ++i)
    {
        const uVec2i &e = edges[i];
        degrees[e.x]++;
        degrees[e.y]++;
    }

    for (uint32_t i = 0; i < vertCount; ++i)
    {
        adj_verts[i].reserve(degrees[i]);
    }

    // Build adjacency list
    for (uint32_t i = 0; i < edgeCount; ++i)
    {
        const uVec2i &e = edges[i];
        adj_verts[e.x].push_back(e.y);
        adj_verts[e.y].push_back(e.x);
    }

    // Remove duplicates and sort each adjacency list
    for (auto &neighbors : adj_verts)
    {
        std::sort(neighbors.begin(), neighbors.end());
        neighbors.erase(std::unique(neighbors.begin(), neighbors.end()), neighbors.end());
    }

    return adj_verts;
}

std::vector<bool> calc_mask(uint32_t vertCount,const std::vector<std::vector<uint32_t>> &adj_verts, VoxelMap &voxel_map)
{
    std::vector<bool> mask(vertCount, false);

    auto voxel_guesses = guess_wire_voxels(voxel_map);
    select_wire_verts(vertCount, adj_verts, voxel_guesses, voxel_map, mask);
    return mask;
}

Vec3 calc_rot_to_forward(std::vector<Vec2> &hull)
{
    std::vector<float> angles = get_edge_angles_2D(hull);
    BoundingBox2D best_box;
    best_box.area = std::numeric_limits<float>::infinity();

    std::vector<Vec2> rot_hull(hull.size());
    for (float angle : angles)
    {
        rotate_points_2D(hull, -angle, rot_hull);
        BoundingBox2D box = compute_aabb_2D(rot_hull, -angle);
        if (box.area < best_box.area)
            best_box = box;
    }

    return {0, 0, best_box.rotation_angle};
}

void standardize_object_transform(const Vec3 *verts, const Vec3 *vert_norms, uint32_t vertCount, const uVec2i *edges, uint32_t edgeCount, Vec3 *out_rot, Vec3 *out_trans)
{
    if (!verts || vertCount == 0 || !vert_norms || vertCount == 0 || !edges || edgeCount == 0 || !out_rot || !out_trans)
        return;

    if (vertCount == 1)
    {
        *out_rot = {0, 0, 0};
        *out_trans = {verts[0].x, verts[0].y, verts[0].z};
        return;
    }
    auto adj_verts = build_adj_vertices(edges, edgeCount, vertCount);
    auto voxel_map = build_voxel_map(verts, vert_norms, vertCount, 0.03f);
    // auto start = std::chrono::high_resolution_clock::now();
    auto mask = calc_mask(vertCount, adj_verts, voxel_map);
    // auto end = std::chrono::high_resolution_clock::now();
    // auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start);
    // std::cout << "Time: " << (float) duration.count() / 1000000 << " ms" << std::endl;

    auto hull2D = convex_hull_2D(verts, vertCount, mask);

    *out_rot = calc_rot_to_forward(hull2D); // Rotation to align object front with +Y axis
    *out_trans = {0, 0, 0};               // Vector from object origin to calculated point of contact
}