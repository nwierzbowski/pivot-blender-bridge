#pragma once

#include "vec.h"

#include <vector>

struct BoundingBox2D {
    Vec2 min_corner;
    Vec2 max_corner;
    float area;
    float rotation_angle;  // Radians

    BoundingBox2D() : area(std::numeric_limits<float>::max()), rotation_angle(0) {}
};

void rotate_points_2D(const std::vector<Vec2> &points, float angle, std::vector<Vec2> &out);

BoundingBox2D compute_aabb_2D(const std::vector<Vec2> &points);

std::vector<Vec2> convex_hull_2D(const Vec3* verts, uint32_t vertCount);

template<typename Selector>
std::vector<Vec2> convex_hull_2D(const Vec3* verts, uint32_t vertCount, Selector select_func);

std::vector<float> get_edge_angles_2D(const std::vector<Vec2> &hull);