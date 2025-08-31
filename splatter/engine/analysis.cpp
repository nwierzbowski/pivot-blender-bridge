#include "analysis.h"
#include "vec.h"
#include "geo2d.h"

#include <vector>
#include <cstdint>
#include <unordered_map>

#include <iostream>
#include <iostream>

std::vector<Vec2> calc_base_convex_hull(const std::vector<Vec3> &verts, BoundingBox3D full_box)
{
    return convex_hull_2D(verts, &Vec3::z, full_box.min_corner.z, full_box.min_corner.z + 0.001);
}

float calc_ratio_full_to_base(const BoundingBox2D &full_box, const BoundingBox2D &base_box)
{
    if (base_box.area == 0)
        return 0;
    return full_box.area / base_box.area;
}

struct Slice
{
    std::vector<uint32_t> vert_indices;
    std::vector<std::vector<Vec2>> chulls;
    float z_upper;
    float z_lower;
    Vec2 cog;
    float area;
};


struct PolyData {
    Vec2 cog;
    float area;
};

PolyData calc_cog_area(const std::vector<Vec2>& vertices) {
    Vec2 centroid = {0.0, 0.0};
    float signedArea = 0.0;

    // A polygon must have at least 3 vertices
    if (vertices.size() < 3) {
        // Handle degenerate cases, e.g., return {0,0} or throw an exception
        return {{0,0}, 0.0};
    }

    for (size_t i = 0; i < vertices.size(); ++i) {
        Vec2 p0 = vertices[i];
        // The next point wraps around to the first for the last vertex
        Vec2 p1 = vertices[(i + 1) % vertices.size()];

        double crossProductTerm = (p0.x * p1.y) - (p1.x * p0.y);
        signedArea += crossProductTerm;
        centroid.x += (p0.x + p1.x) * crossProductTerm;
        centroid.y += (p0.y + p1.y) * crossProductTerm;
    }

    signedArea *= 0.5;

    // Handle cases where the polygon has zero area (e.g., collinear points)
    if (std::fabs(signedArea) < 1e-9) { // Use a small epsilon for float comparison
        // Polygon is degenerate (e.g., a line segment).
        // The centroid is ill-defined by area.
        // A common approach is to return the average of the vertices
        // or a specific error indicator.
        if (!vertices.empty()) {
            Vec2 avg_centroid = {0.0, 0.0};
            for (const auto& p : vertices) {
                avg_centroid.x += p.x;
                avg_centroid.y += p.y;
            }
            avg_centroid.x /= vertices.size();
            avg_centroid.y /= vertices.size();
            return {avg_centroid, std::fabs(signedArea)};
        }
        return {{0,0}, 0.0}; // Default for empty or degenerate
    }

    centroid.x /= (6.0 * signedArea);
    centroid.y /= (6.0 * signedArea);

    return {centroid, std::fabs(signedArea)};
}


// Build per-slice edge buckets: slice_edges[si] contains indices of edges overlapping slice si.
static inline void bucket_edges_per_slice(
    std::vector<std::vector<uint32_t>>& slice_edges,
    const uVec2i* edges,
    uint32_t edgeCount,
    const Vec3* verts,
    float z0,
    float slice_height,
    uint8_t slice_count)
{
    slice_edges.assign(slice_count, {});
    for (uint32_t ei = 0; ei < edgeCount; ++ei) {
        const uVec2i &e = edges[ei];
        float zA = verts[e.x].z;
        float zB = verts[e.y].z;
        float zmin = std::min(zA, zB);
        float zmax = std::max(zA, zB);
        if (zmax <= z0 || zmin >= z0 + slice_height * slice_count)
            continue; // Completely outside vertical span
        // Compute inclusive slice index range this edge overlaps.
        int first = (int)std::floor((zmin - z0) / slice_height);
        int last  = (int)std::floor((zmax - z0) / slice_height);
        if (last < 0 || first >= slice_count) continue;
        if (first < 0) first = 0;
        if (last >= slice_count) last = slice_count - 1;
        // Refine: An edge overlaps slice si if (zmax > zl && zmin < zu). Since we used floor bounds,
        // some slices at the extremities may not actually overlap (e.g. zmax == zl). We check again later.
        for (int si = first; si <= last; ++si)
            slice_edges[si].push_back(ei);
    }
}

// Build slice islands using global connectivity
static inline void build_slice_islands(
    Slice& s,
    const Vec3* verts,
    const uVec2i* edges,
    const std::vector<uint32_t>& slice_edge_indices,
    float z_lower,
    float z_upper,
    uint32_t vertCount,
    std::vector<int32_t>& island_rep,
    auto& uf_find,
    auto& uf_unite)
{
    s.chulls.clear();
    if (slice_edge_indices.empty()) return;

    const float EPS = 1e-8f;

    // Collect vertices in this slice
    std::vector<uint32_t> slice_verts;
    for (uint32_t vid = 0; vid < vertCount; ++vid) {
        float z = verts[vid].z;
        if (z >= z_lower - EPS && z <= z_upper + EPS) {
            slice_verts.push_back(vid);
            if (island_rep[vid] != -1) {
                uf_unite(vid, island_rep[vid]);
            }
        }
    }

    // Union endpoints of overlapping edges
    for (uint32_t ei : slice_edge_indices) {
        const uVec2i &e = edges[ei];
        uf_unite(e.x, e.y);
    }

    // Collect points per component
    std::unordered_map<uint32_t, std::vector<Vec2>> comp_points;
    // Add inside vertices
    for (uint32_t vid : slice_verts) {
        uint32_t cid = uf_find(uf_find, vid);
        comp_points[cid].push_back({verts[vid].x, verts[vid].y});
    }

    // Add intersection points
    for (uint32_t ei : slice_edge_indices) {
        const uVec2i &e = edges[ei];
        uint32_t gidA = e.x;
        uint32_t gidB = e.y;
        const Vec3 &A = verts[gidA];
        const Vec3 &B = verts[gidB];
        float zA = A.z, zB = B.z;
        if (!(std::max(zA, zB) > z_lower && std::min(zA, zB) < z_upper))
            continue;
        uint32_t cid = uf_find(uf_find, gidA);

        bool A_inside = (zA >= z_lower - EPS && zA <= z_upper + EPS);
        bool B_inside = (zB >= z_lower - EPS && zB <= z_upper + EPS);

        if (!A_inside && !B_inside) {
            // Two possible plane intersections (segment spans slice)
            if ((zA - z_lower) * (zB - z_lower) < 0.0f) {
                float t = (z_lower - zA) / (zB - zA);
                comp_points[cid].push_back({A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t});
            }
            if ((zA - z_upper) * (zB - z_upper) < 0.0f) {
                float t = (z_upper - zA) / (zB - zA);
                comp_points[cid].push_back({A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t});
            }
        } else if (A_inside ^ B_inside) {
            // One endpoint inside – add the boundary intersection
            if ((zA - z_lower) * (zB - z_lower) < 0.0f) {
                float t = (z_lower - zA) / (zB - zA);
                comp_points[cid].push_back({A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t});
            } else if ((zA - z_upper) * (zB - z_upper) < 0.0f) {
                float t = (z_upper - zA) / (zB - zA);
                comp_points[cid].push_back({A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t});
            }
        }
        // Both inside: already added
    }

    // Build hulls for components with enough points
    for (auto& [cid, pts] : comp_points) {
        if (pts.size() < 3) continue;
        // Dedupe
        std::sort(pts.begin(), pts.end(), [](const Vec2& a, const Vec2& b) {
            return (a.x < b.x) || (a.x == b.x && a.y < b.y);
        });
        pts.erase(std::unique(pts.begin(), pts.end(), [](const Vec2& a, const Vec2& b) {
            return a.x == b.x && a.y == b.y;
        }), pts.end());
        if (pts.size() < 3) continue;
        auto ch = convex_hull_2D(pts);
        if (!ch.empty()) {
            s.chulls.push_back(std::move(ch));
        }
    }

    // Update island reps for vertices in this slice
    for (uint32_t vid : slice_verts) {
        island_rep[vid] = uf_find(uf_find, vid);
    }
}

// Driver function
Vec3 calc_cog_volume_edges_intersections(const Vec3* verts,
                                         uint32_t vertCount,
                                         const uVec2i* edges,
                                         uint32_t edgeCount,
                                         BoundingBox3D full_box,
                                         float slice_height)
{
    if (!verts || !edges || vertCount == 0 || edgeCount == 0 || slice_height <= 0.f)
        return {0, 0, 0};

    float total_h = full_box.max_corner.z - full_box.min_corner.z;
    if (total_h <= 0.f) return {0, 0, full_box.min_corner.z};

    uint32_t raw_count = (uint32_t)std::ceil(total_h / slice_height);
    uint8_t slice_count = (uint8_t)std::min<uint32_t>(raw_count, 255);

    std::vector<Slice> slices(slice_count);
    for (uint8_t si = 0; si < slice_count; ++si) {
        slices[si].z_lower = full_box.min_corner.z + si * slice_height;
        slices[si].z_upper = std::min(full_box.max_corner.z, slices[si].z_lower + slice_height);
    }

    std::vector<std::vector<uint32_t>> slice_edges;
    bucket_edges_per_slice(slice_edges, edges, edgeCount, verts,
                           full_box.min_corner.z, slice_height, slice_count);

    // Global union-find
    std::vector<uint32_t> uf_parent(vertCount);
    std::vector<uint8_t> uf_rank(vertCount, 0);
    for (uint32_t i = 0; i < vertCount; ++i) uf_parent[i] = i;

    auto uf_find = [&](auto& self, uint32_t x) -> uint32_t {
        if (uf_parent[x] != x) uf_parent[x] = self(self, uf_parent[x]);
        return uf_parent[x];
    };

    auto uf_unite = [&](uint32_t a, uint32_t b) {
        a = uf_find(uf_find, a);
        b = uf_find(uf_find, b);
        if (a == b) return;
        if (uf_rank[a] < uf_rank[b]) std::swap(a, b);
        uf_parent[b] = a;
        if (uf_rank[a] == uf_rank[b]) ++uf_rank[a];
    };

    std::vector<int32_t> island_rep(vertCount, -1);

    for (uint8_t si = 0; si < slice_count; ++si) {
        if (slice_edges[si].empty()) {
            slices[si].area = 0.f;
            continue;
        }
        build_slice_islands(
            slices[si], verts, edges, slice_edges[si],
            slices[si].z_lower, slices[si].z_upper, vertCount,
            island_rep, uf_find, uf_unite
        );

        // Slice COG & area
        Vec2 cog_sum{0, 0};
        float area_sum = 0.f;
        for (auto& h : slices[si].chulls) {
            PolyData pd = calc_cog_area(h);
            if (pd.area <= 0.f) continue;
            cog_sum.x += pd.cog.x * pd.area;
            cog_sum.y += pd.cog.y * pd.area;
            area_sum += pd.area;
        }
        if (area_sum > 0.f) {
            cog_sum.x /= area_sum;
            cog_sum.y /= area_sum;
        }
        slices[si].cog = cog_sum;
        slices[si].area = area_sum;
    }

    // Aggregate
    Vec3 overall{0, 0, 0};
    float total_area = 0.f;
    for (auto& sl : slices) {
        overall.x += sl.cog.x * sl.area;
        overall.y += sl.cog.y * sl.area;
        overall.z += ((sl.z_lower + sl.z_upper) * 0.5f) * sl.area;
        total_area += sl.area;
    }
    if (total_area > 0.f) {
        overall.x /= total_area;
        overall.y /= total_area;
        overall.z /= total_area;
    }
    return overall;
}

