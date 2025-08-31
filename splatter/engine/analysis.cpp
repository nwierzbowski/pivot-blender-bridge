#include "analysis.h"
#include "vec.h"
#include "geo2d.h"

#include <vector>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <set>

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
    const std::vector<float>& vert_z,
    float z0,
    float slice_height,
    uint8_t slice_count)
{
    slice_edges.assign(slice_count, {});
    for (uint32_t ei = 0; ei < edgeCount; ++ei) {
        const uVec2i &e = edges[ei];
        float zA = vert_z[e.x];
        float zB = vert_z[e.y];
        float zmin = std::min(zA, zB);
        float zmax = std::max(zA, zB);
        if (zmax <= z0 || zmin >= z0 + slice_height * slice_count)
            continue; // Completely outside vertical span
        // Compute inclusive slice index range this edge overlaps.
        int first = (int)std::ceil((zmin - z0) / slice_height);
        int last = (int)std::floor((zmax - z0) / slice_height);
        if (first > last) continue;
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
    const std::vector<Vec2>& vert_xy,
    const std::vector<float>& vert_z,
    const uVec2i* edges,
    const std::vector<uint32_t>& slice_edge_indices,
    float z_lower,
    float z_upper,
    const std::vector<uint32_t>& slice_verts,
    const std::vector<uint32_t>& vertex_comp,
    const std::vector<uint32_t>& cid_to_index,
    uint32_t num_components)
{
    s.chulls.clear();
    if (slice_edge_indices.empty()) return;

    const float EPS = 1e-8f;

    // Count points per component for sizing
    std::vector<size_t> component_sizes(num_components, 0);
    for (uint32_t vid : slice_verts) {
        uint32_t cid = vertex_comp[vid];
        uint32_t idx = cid_to_index[cid];
        component_sizes[idx]++;
    }
    for (uint32_t ei : slice_edge_indices) {
        const uVec2i &e = edges[ei];
        uint32_t gidA = e.x;
        uint32_t gidB = e.y;
        float zA = vert_z[gidA];
        float zB = vert_z[gidB];
        float d = zB - zA;
        if (std::abs(d) < 1e-8f) continue;
        uint32_t cid = vertex_comp[gidA];
        uint32_t idx = cid_to_index[cid];

        bool A_inside = (zA >= z_lower - EPS && zA <= z_upper + EPS);
        bool B_inside = (zB >= z_lower - EPS && zB <= z_upper + EPS);

        if (!A_inside && !B_inside) {
            if ((zA - z_lower) * (zB - z_lower) < 0.0f) component_sizes[idx]++;
            if ((zA - z_upper) * (zB - z_upper) < 0.0f) component_sizes[idx]++;
        } else if (A_inside ^ B_inside) {
            if ((zA - z_lower) * (zB - z_lower) < 0.0f) component_sizes[idx]++;
            else if ((zA - z_upper) * (zB - z_upper) < 0.0f) component_sizes[idx]++;
        }
    }

    // Allocate contiguous storage
    std::vector<size_t> component_starts(num_components + 1, 0);
    size_t total_points = 0;
    for (size_t i = 0; i < num_components; ++i) {
        component_starts[i] = total_points;
        total_points += component_sizes[i];
    }
    component_starts[num_components] = total_points;
    std::vector<Vec2> all_points(total_points);

    // Place points in contiguous array
    std::vector<size_t> current_pos = component_starts;
    for (uint32_t vid : slice_verts) {
        uint32_t cid = vertex_comp[vid];
        uint32_t idx = cid_to_index[cid];
        all_points[current_pos[idx]] = {vert_xy[vid].x, vert_xy[vid].y};
        current_pos[idx]++;
    }
    for (uint32_t ei : slice_edge_indices) {
        const uVec2i &e = edges[ei];
        uint32_t gidA = e.x;
        uint32_t gidB = e.y;
        const Vec2 &A_xy = vert_xy[gidA];
        const Vec2 &B_xy = vert_xy[gidB];
        float zA = vert_z[gidA];
        float zB = vert_z[gidB];
        float d = zB - zA;
        if (std::abs(d) < 1e-8f) continue;
        uint32_t cid = vertex_comp[gidA];
        uint32_t idx = cid_to_index[cid];

        bool A_inside = (zA >= z_lower - EPS && zA <= z_upper + EPS);
        bool B_inside = (zB >= z_lower - EPS && zB <= z_upper + EPS);

        if (!A_inside && !B_inside) {
            if ((zA - z_lower) * (zB - z_lower) < 0.0f) {
                float t = (z_lower - zA) / d;
                all_points[current_pos[idx]] = {A_xy.x + (B_xy.x - A_xy.x) * t, A_xy.y + (B_xy.y - A_xy.y) * t};
                current_pos[idx]++;
            }
            if ((zA - z_upper) * (zB - z_upper) < 0.0f) {
                float t = (z_upper - zA) / d;
                all_points[current_pos[idx]] = {A_xy.x + (B_xy.x - A_xy.x) * t, A_xy.y + (B_xy.y - A_xy.y) * t};
                current_pos[idx]++;
            }
        } else if (A_inside ^ B_inside) {
            if ((zA - z_lower) * (zB - z_lower) < 0.0f) {
                float t = (z_lower - zA) / d;
                all_points[current_pos[idx]] = {A_xy.x + (B_xy.x - A_xy.x) * t, A_xy.y + (B_xy.y - A_xy.y) * t};
                current_pos[idx]++;
            } else if ((zA - z_upper) * (zB - z_upper) < 0.0f) {
                float t = (z_upper - zA) / d;
                all_points[current_pos[idx]] = {A_xy.x + (B_xy.x - A_xy.x) * t, A_xy.y + (B_xy.y - A_xy.y) * t};
                current_pos[idx]++;
            }
        }
    }

    // Process each component's contiguous range
    auto cmp = [](const Vec2& a, const Vec2& b) {
        return (a.x < b.x) || (a.x == b.x && a.y < b.y);
    };
    auto eq = [](const Vec2& a, const Vec2& b) {
        return a.x == b.x && a.y == b.y;
    };
    for (size_t i = 0; i < num_components; ++i) {
        size_t start = component_starts[i];
        size_t end = component_starts[i + 1];
        if (end - start < 3) continue;

        auto pts_begin = all_points.begin() + start;
        auto pts_end = all_points.begin() + end;
        std::sort(pts_begin, pts_end, cmp);
        auto new_end = std::unique(pts_begin, pts_end, eq);
        size_t new_size = new_end - pts_begin;
        if (new_size < 3) continue;

        std::vector<Vec2> hull_input(pts_begin, new_end);
        auto ch = convex_hull_2D(hull_input);
        if (!ch.empty()) {
            s.chulls.push_back(std::move(ch));
        }
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

    // Precompute vertex data for cache efficiency
    std::vector<float> vert_z(vertCount);
    std::vector<Vec2> vert_xy(vertCount);
    for (uint32_t i = 0; i < vertCount; ++i) {
        vert_z[i] = verts[i].z;
        vert_xy[i] = {verts[i].x, verts[i].y};
    }

    // Precompute edge z-values for cache efficiency
    std::vector<float> edge_zA(edgeCount);
    std::vector<float> edge_zB(edgeCount);
    for (uint32_t ei = 0; ei < edgeCount; ++ei) {
        edge_zA[ei] = vert_z[edges[ei].x];
        edge_zB[ei] = vert_z[edges[ei].y];
    }

    uint32_t raw_count = (uint32_t)std::ceil(total_h / slice_height);
    uint8_t slice_count = (uint8_t)std::min<uint32_t>(raw_count, 255);

    std::vector<Slice> slices(slice_count);
    for (uint8_t si = 0; si < slice_count; ++si) {
        slices[si].z_lower = full_box.min_corner.z + si * slice_height;
        slices[si].z_upper = std::min(full_box.max_corner.z, slices[si].z_lower + slice_height);
    }

    std::vector<std::vector<uint32_t>> slice_edges;
    bucket_edges_per_slice(slice_edges, edges, edgeCount, vert_z,
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

    std::vector<std::vector<uint32_t>> slice_vertices(slice_count);
    for (uint32_t vid = 0; vid < vertCount; ++vid) {
        float z = vert_z[vid];
        if (z < full_box.min_corner.z || z > full_box.max_corner.z) continue;
        int si = (int)std::floor((z - full_box.min_corner.z) / slice_height);
        if (si >= 0 && si < slice_count) {
            slice_vertices[si].push_back(vid);
        }
    }

    // Union all edges globally for connectivity
    for (uint32_t ei = 0; ei < edgeCount; ++ei) {
        const uVec2i &e = edges[ei];
        uf_unite(e.x, e.y);
    }

    // Precompute component roots for all vertices
    std::vector<uint32_t> vertex_comp(vertCount);
    for (uint32_t i = 0; i < vertCount; ++i) {
        vertex_comp[i] = uf_find(uf_find, i);
    }

    // Collect unique component ids and map to consecutive indices
    std::unordered_set<uint32_t> unique_cids;
    for (uint32_t i = 0; i < vertCount; ++i) {
        unique_cids.insert(vertex_comp[i]);
    }
    uint32_t max_cid = 0;
    for (uint32_t cid : unique_cids) max_cid = std::max(max_cid, cid);
    std::vector<uint32_t> cid_to_index(max_cid + 1, -1);
    uint32_t num_components = 0;
    for (uint32_t cid : unique_cids) {
        cid_to_index[cid] = num_components++;
    }

    for (uint8_t si = 0; si < slice_count; ++si) {
        if (slice_edges[si].empty()) {
            slices[si].area = 0.f;
            continue;
        }
        build_slice_islands(
            slices[si], vert_xy, vert_z, edges, slice_edges[si],
            slices[si].z_lower, slices[si].z_upper, slice_vertices[si],
            vertex_comp, cid_to_index, num_components
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

