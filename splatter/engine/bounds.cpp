#include "bounds.h"
#include "vec.h"
#include "geo2d.h"

#include <vector>


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