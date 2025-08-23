#include "bounds.h"
#include "util.h"
#include "chull.h"

#include <Eigen/Eigenvalues>
#include <nanoflann.hpp>

#include <iostream>
#include <cstdint>
#include <vector>
#include <cmath>
#include <algorithm>
#include <queue>
#include <chrono>
#include <random>
#include <limits>

// Rotate points by angle (radians) around origin
void rotate_points_2D(const std::vector<Vec2> &points, float angle, std::vector<Vec2> &out)
{
    float cos_a = std::cos(angle);
    float sin_a = std::sin(angle);

    for (size_t i = 0; i < points.size(); ++i)
    {
        const Vec2 &p = points[i];
        out[i] = {
            p.x * cos_a - p.y * sin_a,
            p.x * sin_a + p.y * cos_a};
    }
}

// Compute axis-aligned bounding box of points
BoundingBox2D compute_aabb_2D(const std::vector<Vec2> &points, float rotation_angle)
{
    if (points.empty())
        return {};

    float min_x = points[0].x, max_x = points[0].x;
    float min_y = points[0].y, max_y = points[0].y;

    for (const Vec2 &p : points)
    {
        min_x = std::min(min_x, p.x);
        max_x = std::max(max_x, p.x);
        min_y = std::min(min_y, p.y);
        max_y = std::max(max_y, p.y);
    }

    BoundingBox2D box;
    box.min_corner = {min_x, min_y};
    box.max_corner = {max_x, max_y};
    box.area = (max_x - min_x) * (max_y - min_y);
    box.rotation_angle = rotation_angle;

    return box;
}

// Get unique edge directions from convex hull
std::vector<float> get_edge_angles_2D(const std::vector<Vec2> &hull)
{
    std::vector<float> angles;
    angles.reserve(hull.size());

    for (size_t i = 0; i < hull.size(); ++i)
    {
        size_t next = (i + 1) % hull.size();
        Vec2 edge = hull[next] - hull[i];

        if (edge.length_squared() > 1e-8f)
        { // Avoid degenerate edges
            float angle = std::atan2(edge.y, edge.x);

            // Normalize to [0, π) since we only need half rotations for rectangles
            // if (angle < 0) angle += M_PI;
            // if (angle >= M_PI) angle -= M_PI;

            angles.push_back(angle);
        }
    }

    // Remove duplicate angles (within tolerance)
    // std::sort(angles.begin(), angles.end());
    // auto last = std::unique(angles.begin(), angles.end(),
    //     [](float a, float b) { return std::abs(a - b) < 1e-6f; });
    // angles.erase(last, angles.end());

    return angles;
}

static inline void eig3(const float A[3][3], float &lambda1, float &lambda2)
{
    // Fast power-iteration for largest eigenvalue + deflation for second.
    // Fall back to Eigen if something goes wrong.
    auto dot3 = [](const float a[3], const float b[3])
    {
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    };
    auto mat_vec = [&](const float M[3][3], const float v[3], float out[3])
    {
        for (int r = 0; r < 3; ++r)
            out[r] = M[r][0] * v[0] + M[r][1] * v[1] + M[r][2] * v[2];
    };

    float M[3][3];
    for (int r = 0; r < 3; ++r)
        for (int c = 0; c < 3; ++c)
            M[r][c] = A[r][c];

    const int MAX_IT = 40;
    const float TOL = 1e-10f;

    // First eigenpair
    float v[3] = {1.0f, 1.0f, 1.0f};
    float tmp[3];
    float nrm = std::sqrt(dot3(v, v));
    if (nrm == 0.0f)
    {
        v[0] = 1;
        v[1] = 0;
        v[2] = 0;
        nrm = 1.0f;
    }
    v[0] /= nrm;
    v[1] /= nrm;
    v[2] /= nrm;
    float lambda_prev = 0.0f;
    for (int it = 0; it < MAX_IT; ++it)
    {
        mat_vec(M, v, tmp);
        float tmpn = std::sqrt(dot3(tmp, tmp));
        if (tmpn == 0.0f)
            break;
        v[0] = tmp[0] / tmpn;
        v[1] = tmp[1] / tmpn;
        v[2] = tmp[2] / tmpn;
        mat_vec(M, v, tmp);
        float lambda = dot3(v, tmp);
        if (std::abs(lambda - lambda_prev) < TOL * std::max(1.0f, std::abs(lambda)))
        {
            lambda_prev = lambda;
            break;
        }
        lambda_prev = lambda;
    }
    lambda1 = lambda_prev;

    // Deflate and find second eigenvector (use original M to compute Rayleigh quotient)
    float M2[3][3];
    for (int r = 0; r < 3; ++r)
        for (int c = 0; c < 3; ++c)
            M2[r][c] = M[r][c] - lambda1 * v[r] * v[c];

    float u[3] = {v[1] - v[2] + 1e-1f, v[2] - v[0] + 1e-1f, v[0] - v[1] + 1e-1f};
    nrm = std::sqrt(dot3(u, u));
    if (nrm == 0.0f)
    {
        u[0] = 1;
        u[1] = 0;
        u[2] = 0;
        nrm = 1.0f;
    }
    u[0] /= nrm;
    u[1] /= nrm;
    u[2] /= nrm;
    float lambda2_prev = 0.0f;
    for (int it = 0; it < MAX_IT; ++it)
    {
        mat_vec(M2, u, tmp);
        float tmpn = std::sqrt(dot3(tmp, tmp));
        if (tmpn == 0.0f)
            break;
        u[0] = tmp[0] / tmpn;
        u[1] = tmp[1] / tmpn;
        u[2] = tmp[2] / tmpn;
        mat_vec(M, u, tmp); // original matrix for Rayleigh
        float lambda = dot3(u, tmp);
        if (std::abs(lambda - lambda2_prev) < TOL * std::max(1.0f, std::abs(lambda)))
        {
            lambda2_prev = lambda;
            break;
        }
        lambda2_prev = lambda;
    }
    lambda2 = lambda2_prev;

    // Ordering and safety
    if (!std::isfinite(lambda1) || !std::isfinite(lambda2) || lambda2 > lambda1 + 1e-12)
    {
        // fallback to robust Eigen solver
        Eigen::Matrix3d E;
        E << A[0][0], A[0][1], A[0][2],
            A[1][0], A[1][1], A[1][2],
            A[2][0], A[2][1], A[2][2];
        Eigen::SelfAdjointEigenSolver<Eigen::Matrix3d> es;
        es.compute(E);
        if (es.info() == Eigen::Success)
        {
            Eigen::Vector3d w = es.eigenvalues(); // ascending
            lambda1 = w[2];
            lambda2 = w[1];
        }
        else
        {
            lambda1 = lambda2 = 0.0;
        }
    }
};

std::vector<bool> elim_wires(const Vec3 *verts, uint32_t vertCount, const std::vector<std::vector<uint32_t>> &adj_verts)
{
    if (!verts || vertCount == 0)
        return std::vector<bool>(vertCount, false);

    // Parameters
    const uint32_t K = std::min<uint32_t>(70, vertCount); // neighborhood size
    const float LINEARITY_THRESHOLD = 0.9f;
    // const uint8_t MIN_WIRE_GROUP_SIZE = 10;

    // Helper: compute covariance matrix (3x3) for a set of points given their indices
    auto compute_cov = [&](const std::vector<uint32_t> &idxs, float cov[3][3])
    {
        const size_t n = idxs.size();
        float mean[3] = {0.0f, 0.0f, 0.0f};
        for (uint32_t id : idxs)
        {
            const Vec3 &p = verts[id];
            mean[0] += p.x;
            mean[1] += p.y;
            mean[2] += p.z;
        }
        mean[0] /= n;
        mean[1] /= n;
        mean[2] /= n;
        // zero cov
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 3; ++c)
                cov[r][c] = 0.0;
        for (uint32_t id : idxs)
        {
            const Vec3 &p = verts[id];
            float d0 = p.x - mean[0];
            float d1 = p.y - mean[1];
            float d2 = p.z - mean[2];
            cov[0][0] += d0 * d0;
            cov[0][1] += d0 * d1;
            cov[0][2] += d0 * d2;
            cov[1][0] += d1 * d0;
            cov[1][1] += d1 * d1;
            cov[1][2] += d1 * d2;
            cov[2][0] += d2 * d0;
            cov[2][1] += d2 * d1;
            cov[2][2] += d2 * d2;
        }
        // Normalize by n
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 3; ++c)
                cov[r][c] /= static_cast<double>(n);
    };

    auto start = std::chrono::high_resolution_clock::now();

    std::vector<bool> is_wire(vertCount, false);
    std::vector<float> linearity_scores(vertCount, 0.0f);

    std::vector<float> total_weights(vertCount, 0.0f);
    std::vector<float> votes(vertCount, 0.0f);

    // --- Replaced BFS data structures with Dijkstra structures ---
    std::vector<int32_t> visit_tag(vertCount, -1);          // marks last source index that touched this node
    std::vector<float>   graph_dist(vertCount, 0.0f);       // distance from current source
    std::vector<uint32_t> neighbor_idxs;
    neighbor_idxs.reserve(K);
    // ------------------------------------------------------------

    for (uint32_t i = 0; i < vertCount; i += 24)
    {
        // --- Dijkstra (early exit after collecting K nearest) ---
        neighbor_idxs.clear();

        using HeapItem = std::pair<float, uint32_t>;
        struct Cmp { bool operator()(const HeapItem& a, const HeapItem& b) const { return a.first > b.first; } };
        std::priority_queue<HeapItem, std::vector<HeapItem>, Cmp> pq;

        pq.emplace(0.0f, i);
        visit_tag[i] = static_cast<int32_t>(i);
        graph_dist[i] = 0.0f;

        while (!pq.empty() && neighbor_idxs.size() < K)
        {
            auto [dist_u, u] = pq.top();
            pq.pop();

            // Skip stale entries
            if (visit_tag[u] != static_cast<int32_t>(i) || dist_u != graph_dist[u]) continue;

            neighbor_idxs.push_back(u);

            // Expand neighbors
            const Vec3 &pu = verts[u];
            for (uint32_t v : adj_verts[u])
            {
                const Vec3 &pv = verts[v];
                float dx = pv.x - pu.x;
                float dy = pv.y - pu.y;
                float dz = pv.z - pu.z;
                float w = std::sqrt(dx * dx + dy * dy + dz * dz); // edge weight (Euclidean)

                if (w <= 0.0f) continue;

                float newDist = dist_u + w;
                if (visit_tag[v] != static_cast<int32_t>(i) || newDist < graph_dist[v])
                {
                    graph_dist[v] = newDist;
                    visit_tag[v] = static_cast<int32_t>(i);
                    pq.emplace(newDist, v);
                }
            }
        }

        if (neighbor_idxs.empty())
            neighbor_idxs.push_back(i);
        // ---------------------------------------------------------

        // compute covariance
        float cov[3][3];
        compute_cov(neighbor_idxs, cov);

        // compute eigenvalues
        float lambda1, lambda2;
        eig3(cov, lambda1, lambda2);

        float lin = 0.0f;
        if (lambda1 > 0.0f)
            lin = (lambda1 - lambda2) / lambda1;
        linearity_scores[i] = lin;

        // Accumulate votes for neighbors (skip source itself)
        for (auto it = neighbor_idxs.begin() + (neighbor_idxs.size() > 1 ? 1 : 0); it != neighbor_idxs.end(); ++it)
        {
            uint32_t idx_n = *it;
            // Only use nodes actually visited in this Dijkstra round
            if (visit_tag[idx_n] != static_cast<int32_t>(i)) continue;
            float d = graph_dist[idx_n];
            if (d <= 0.0f) continue;
            float weight = 1.0f / (d * d);
            total_weights[idx_n] += weight;
            votes[idx_n] += weight * lin;
        }
    }

    for (uint32_t i = 0; i < vertCount; ++i)
    {
        if (linearity_scores[i] == 0.0f)
        {
            linearity_scores[i] = votes[i] / (total_weights[i] + 1e-6f);
        }
        is_wire[i] = (linearity_scores[i] > LINEARITY_THRESHOLD);
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    std::cout << "Time to compute linearity: " << duration.count() << " ms" << std::endl;

    std::vector<bool> group_visited(vertCount, false);
    std::vector<int> boundary_indices;

    // Populate final_is_wire
    // start = std::chrono::high_resolution_clock::now();
    for (uint32_t i = 0; i < vertCount; ++i)
    {
        if (is_wire[i] && group_visited[i] == false)
        {
            std::vector<uint32_t> group;
            std::queue<uint32_t> queue;
            std::vector<uint32_t> current_bounds;
            queue.push(i);
            group_visited[i] = true;
            while (!queue.empty())
            {
                uint32_t idx = queue.front();
                queue.pop();
                group.push_back(idx);

                // Check neighbors
                for (uint32_t neighbor : adj_verts[idx])
                {
                    if (is_wire[neighbor] && !group_visited[neighbor])
                    {
                        group_visited[neighbor] = true;
                        queue.push(neighbor);
                    }
                    else if (!is_wire[neighbor] && std::find(current_bounds.begin(), current_bounds.end(), neighbor) == current_bounds.end())
                    {
                        current_bounds.push_back(neighbor);
                    }
                }
            }

            // If group is large enough or is it's whole island, mark all as wire
            if (group.size() < 10 && !current_bounds.empty())
            {
                for (uint32_t idx : group)
                {
                    is_wire[idx] = false;
                }
                
            } else {
                for (uint32_t idx : current_bounds)
                {
                    boundary_indices.push_back(idx);
                }
            }
        }
    }
    // end = std::chrono::high_resolution_clock::now();
    // duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    // std::cout << "Time to eliminate small wire groups: " << duration.count() << " ms" << std::endl;

    std::queue<uint32_t> queue;
    // start = std::chrono::high_resolution_clock::now();
    for (uint32_t idx : boundary_indices)
    {
        queue.push(idx);
    }

    while (!queue.empty())
    {
        uint32_t current = queue.front();
        queue.pop();

        if (linearity_scores[current] > 0.1 && !is_wire[current])
        {

            is_wire[current] = true;
            // Check neighbors
            for (uint32_t neighbor : adj_verts[current])
            {
                if (!is_wire[neighbor])
                {
                    queue.push(neighbor);
                }
            }
        }
    }
    // end = std::chrono::high_resolution_clock::now();
    // duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    // std::cout << "Time to grow wire selection: " << duration.count() << " ms" << std::endl;
    // uint32_t wire_count = 0;
    // for (uint32_t i = 0; i < is_wire.size(); ++i)
    // {
    //     if (is_wire[i])
    //     {
    //         printf("%i ", i);
    //         wire_count++;
    //     }
    // }

    // std::cout << "Number of wire vertices: " << wire_count << std::endl;

    return is_wire;
}

void build_adj_vertices(const Vec3 *verts, uint32_t vertCount, const uVec3i *faces, uint32_t faceCount, std::vector<std::vector<uint32_t>> &out_adj_verts)
{
    if (!verts || vertCount == 0 || !faces || faceCount == 0)
        return;

    // Build adjacency list
    for (uint32_t i = 0; i < faceCount; ++i)
    {
        const uVec3i &f = faces[i];
        if (f.x < vertCount && f.y < vertCount)
        {
            out_adj_verts[f.x].push_back(f.y);
            out_adj_verts[f.y].push_back(f.x);
        }
        if (f.y < vertCount && f.z < vertCount)
        {
            out_adj_verts[f.y].push_back(f.z);
            out_adj_verts[f.z].push_back(f.y);
        }
        if (f.z < vertCount && f.x < vertCount)
        {
            out_adj_verts[f.z].push_back(f.x);
            out_adj_verts[f.x].push_back(f.z);
        }
    }

    // Remove duplicates and sort each adjacency list
    for (auto &neighbors : out_adj_verts)
    {
        std::sort(neighbors.begin(), neighbors.end());
        neighbors.erase(std::unique(neighbors.begin(), neighbors.end()), neighbors.end());
    }
}

void align_min_bounds(const Vec3 *verts, uint32_t vertCount, const uVec3i *faces, uint32_t faceCount, Vec3 *out_rot, Vec3 *out_trans)
{
    if (!verts || vertCount == 0 || !faces || faceCount == 0 || !out_rot || !out_trans)
        return;

    if (vertCount == 1)
    {
        *out_rot = {0, 0, 0};
        *out_trans = {verts[0].x, verts[0].y, verts[0].z};
        return;
    }

    // Calculate vertex adjacency lists
    std::vector<std::vector<uint32_t>> adj_verts(vertCount);
    build_adj_vertices(verts, vertCount, faces, faceCount, adj_verts);

    auto start = std::chrono::high_resolution_clock::now();

    auto is_wire = elim_wires(verts, vertCount, adj_verts);

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    std::cout << "Time: " << duration.count() << " ms" << std::endl;

    // auto is_wire = std::vector<bool>(vertCount, false);
    // timeFunction([&]() { is_wire = elim_wires(verts, vertCount, adj_verts); });

    std::vector<Vec2> hull = convex_hull_2D(verts, vertCount, is_wire);
    std::vector<float> angles = get_edge_angles_2D(hull);

    BoundingBox2D best_box;

    std::vector<Vec2> rot_hull;
    rot_hull.resize(hull.size());

    for (float angle : angles)
    {
        rotate_points_2D(hull, -angle, rot_hull);
        BoundingBox2D box = compute_aabb_2D(rot_hull, -angle);

        if (box.area < best_box.area)
        {
            best_box = box;
        }
    }
    *out_rot = {0, 0, best_box.rotation_angle};
    *out_trans = {0, 0, 0};
    return;
}