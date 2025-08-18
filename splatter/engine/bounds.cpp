#include "bounds.h"
#include "util.h"
#include "chull.h"

#include <cstdint>
#include <vector>
#include <cmath>
#include <algorithm>

// Rotate points by angle (radians) around origin
std::vector<PT> rotate_points(const std::vector<PT>& points, float angle) {
    float cos_a = std::cos(angle);
    float sin_a = std::sin(angle);
    
    std::vector<PT> rotated;
    rotated.reserve(points.size());

    for (const PT& p : points) {
        rotated.emplace_back(PT{
            p.x * cos_a - p.y * sin_a,
            p.x * sin_a + p.y * cos_a
        });
    }
    
    return rotated;
}

// Compute axis-aligned bounding box of points
BoundingBox compute_aabb(const std::vector<PT>& points, float rotation_angle) {
    if (points.empty()) return {};
    
    float min_x = points[0].x, max_x = points[0].x;
    float min_y = points[0].y, max_y = points[0].y;
    
    for (const PT& p : points) {
        min_x = std::min(min_x, p.x);
        max_x = std::max(max_x, p.x);
        min_y = std::min(min_y, p.y);
        max_y = std::max(max_y, p.y);
    }
    
    BoundingBox box;
    box.min_corner = {min_x, min_y};
    box.max_corner = {max_x, max_y};
    box.area = (max_x - min_x) * (max_y - min_y);
    box.center = {(min_x + max_x) * 0.5f, (min_y + max_y) * 0.5f};
    box.rotation_angle = rotation_angle;
    
    return box;
}

// Get unique edge directions from convex hull
std::vector<float> get_edge_angles(const std::vector<PT>& hull) {
    std::vector<float> angles;
    angles.reserve(hull.size());
    
    for (size_t i = 0; i < hull.size(); ++i) {
        size_t next = (i + 1) % hull.size();
        PT edge = hull[next] - hull[i];
        
        if (edge.length_squared() > 1e-8f) {  // Avoid degenerate edges
            float angle = std::atan2(edge.y, edge.x);
            
            // Normalize to [0, π) since we only need half rotations for rectangles
            if (angle < 0) angle += M_PI;
            if (angle >= M_PI) angle -= M_PI;
            
            angles.push_back(angle);
        }
    }
    
    // Remove duplicate angles (within tolerance)
    std::sort(angles.begin(), angles.end());
    auto last = std::unique(angles.begin(), angles.end(), 
        [](float a, float b) { return std::abs(a - b) < 1e-6f; });
    angles.erase(last, angles.end());
    
    return angles;
}

void align_min_bounds(const Vec3* verts, uint32_t vertCount, Vec3* out_rot, Vec3* out_trans) {
    if (!verts || vertCount == 0 || !out_rot || !out_trans) return;

    if (vertCount == 1) {
        *out_rot = {0, 0, 0};
        *out_trans = {verts[0].x, verts[0].y, verts[0].z};
        return;
    }

    std::vector<PT> hull = convex_hull_2D(verts, vertCount);
    std::vector<float> angles = get_edge_angles(hull);

    BoundingBox best_box;

    for (float angle : angles) {
        auto rotated_hull = rotate_points(hull, angle);
        BoundingBox box = compute_aabb(rotated_hull, angle);

        if (box.area < best_box.area) {
            best_box = box;
        }
    }
    *out_rot = {0, 0, best_box.rotation_angle};
    *out_trans = {0, 0, 0};
    return;
}