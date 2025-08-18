from libc.stdint cimport uint32_t

from splatter.cython_api.bounds_api cimport align_min_bounds as align_min_bounds_cpp
from splatter.cython_api.util_api cimport Vec3

def align_min_bounds(float[:, ::1] verts):
    """Calls the C++ function to compute the convex hull in 2D."""

    if verts.shape[0] == 0:
        return # Or raise an error
    if verts.shape[1] != 3:
        raise ValueError(f"Input array must be Nx3, but got Nx{verts.shape[1]}")

    cdef Vec3* verts_ptr = <Vec3*> &verts[0, 0]
    cdef uint32_t vertCount = verts.shape[0]

    cdef Vec3 out_rot, out_trans
    with nogil:
        align_min_bounds_cpp(verts_ptr, vertCount, &out_rot, &out_trans)

    return (out_rot.x, out_rot.y, out_rot.z), (out_trans.x, out_trans.y, out_trans.z)