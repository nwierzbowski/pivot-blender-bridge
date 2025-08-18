from libc.stdint cimport uint32_t
from splatter.cython_api.util_api cimport Vec3

cdef extern from "../engine/bounds.h" nogil:
    void align_min_bounds(const Vec3* verts, uint32_t vertCount, Vec3* out_rot, Vec3* out_trans)
