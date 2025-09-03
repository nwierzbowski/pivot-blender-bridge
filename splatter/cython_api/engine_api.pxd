from libc.stdint cimport uint32_t
from splatter.cython_api.vec_api cimport Vec3, uVec2i

cdef extern from "../engine/engine.h" nogil:
    void standardize_object_transform(const Vec3 *verts, uint32_t vertCount, const uVec2i *edges, uint32_t edgeCount, Vec3 *out_rot, Vec3 *out_trans);
