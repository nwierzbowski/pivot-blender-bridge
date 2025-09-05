from libc.stdint cimport uint32_t
from libc.stdlib cimport malloc, free

from splatter.cython_api.engine_api cimport prepare_object_batch as prepare_object_batch_cpp
from splatter.cython_api.vec_api cimport Vec3, uVec2i

def align_min_bounds(float[:, ::1] verts_flat, uint32_t[:, ::1] edges_flat, list vert_counts, list edge_counts):
    cdef uint32_t num_objects = len(vert_counts)
    if num_objects == 0:
        return [], []
    
    # Pre-copy Python lists to C arrays for nogil access
    cdef uint32_t *vert_counts_ptr = <uint32_t *>malloc(num_objects * sizeof(uint32_t))
    cdef uint32_t *edge_counts_ptr = <uint32_t *>malloc(num_objects * sizeof(uint32_t))
    for i in range(num_objects):
        vert_counts_ptr[i] = vert_counts[i]
        edge_counts_ptr[i] = edge_counts[i]
    
    cdef Vec3 *verts_ptr = <Vec3 *> &verts_flat[0, 0]
    cdef uVec2i *edges_ptr = <uVec2i *> &edges_flat[0, 0]
    
    cdef Vec3 *out_rots = <Vec3 *> malloc(num_objects * sizeof(Vec3))
    cdef Vec3 *out_trans = <Vec3 *> malloc(num_objects * sizeof(Vec3))
    
    with nogil:
        prepare_object_batch_cpp(verts_ptr, edges_ptr, vert_counts_ptr, edge_counts_ptr, num_objects, out_rots, out_trans)
    
    # Convert results to Python lists
    rots = [(out_rots[i].x, out_rots[i].y, out_rots[i].z) for i in range(num_objects)]
    trans = [(out_trans[i].x, out_trans[i].y, out_trans[i].z) for i in range(num_objects)]
    
    free(vert_counts_ptr)
    free(edge_counts_ptr)
    free(out_rots)
    free(out_trans)
    
    return rots, trans