from libc.stdint cimport uint32_t
from libc.stdlib cimport malloc, free
from mathutils import Quaternion as MathutilsQuaternion

cimport numpy as cnp

import bpy
import numpy as np
import time

from splatter.cython_api.engine_api cimport prepare_object_batch as prepare_object_batch_cpp
from splatter.cython_api.engine_api cimport group_objects as group_objects_cpp
from splatter.cython_api.engine_api cimport apply_rotation as apply_rotation_cpp

from splatter.cython_api.vec_api cimport Vec3, uVec2i
from splatter.cython_api.quaternion_api cimport Quaternion

def align_min_bounds(float[::1] verts_flat, uint32_t[::1] edges_flat, list vert_counts, list edge_counts):
    cdef uint32_t num_objects = len(vert_counts)
    if num_objects == 0:
        return [], []
    
    # Pre-copy Python lists to C arrays for nogil access
    cdef uint32_t *vert_counts_ptr = <uint32_t *>malloc(num_objects * sizeof(uint32_t))
    cdef uint32_t *edge_counts_ptr = <uint32_t *>malloc(num_objects * sizeof(uint32_t))
    for i in range(num_objects):
        vert_counts_ptr[i] = vert_counts[i]
        edge_counts_ptr[i] = edge_counts[i]

    cdef Vec3 *verts_ptr = <Vec3 *> &verts_flat[0]
    cdef uVec2i *edges_ptr = <uVec2i *> &edges_flat[0]

    cdef Quaternion *out_rots = <Quaternion *> malloc(num_objects * sizeof(Quaternion))
    cdef Vec3 *out_trans = <Vec3 *> malloc(num_objects * sizeof(Vec3))
    
    with nogil:

        prepare_object_batch_cpp(verts_ptr, edges_ptr, vert_counts_ptr, edge_counts_ptr, num_objects, out_rots, out_trans)
    
    # Convert results to Python lists
    rots = [MathutilsQuaternion((out_rots[i].w, out_rots[i].x, out_rots[i].y, out_rots[i].z)) for i in range(num_objects)]
    trans = [(out_trans[i].x, out_trans[i].y, out_trans[i].z) for i in range(num_objects)]
    
    free(vert_counts_ptr)
    free(edge_counts_ptr)
    free(out_rots)
    free(out_trans)
    
    return rots, trans

# def group_objects(float[:, ::1] verts_flat, uint32_t[:, ::1] edges_flat, list vert_counts, list edge_counts, list offsets, list rotations):
#     cdef uint32_t num_objects = len(vert_counts)
#     if num_objects == 0:
#         return
    
#     # Pre-copy Python lists to C arrays
#     cdef uint32_t *vert_counts_ptr = <uint32_t *>malloc(num_objects * sizeof(uint32_t))
#     cdef uint32_t *edge_counts_ptr = <uint32_t *>malloc(num_objects * sizeof(uint32_t))
#     cdef Vec3 *offsets_ptr = <Vec3 *>malloc(num_objects * sizeof(Vec3))
#     cdef Quaternion *rotations_ptr = <Quaternion *>malloc(num_objects * sizeof(Quaternion))
#     for i in range(num_objects):
#         vert_counts_ptr[i] = vert_counts[i]
#         edge_counts_ptr[i] = edge_counts[i]
#         offsets_ptr[i] = Vec3(offsets[i][0], offsets[i][1], offsets[i][2])
#         rotations_ptr[i] = Quaternion(rotations[i].w, rotations[i].x, rotations[i].y, rotations[i].z)

#     with nogil:
#         group_objects_cpp(verts_flat, edges_flat, vert_counts_ptr, edge_counts_ptr, offsets_ptr, rotations_ptr, num_objects)
    
#     free(vert_counts_ptr)
#     free(edge_counts_ptr)
#     free(offsets_ptr)
#     free(rotations_ptr)


def apply_rotation(float[::1] verts, uint32_t vert_count, rotation):
    cdef Vec3 *verts_ptr = <Vec3 *> &verts[0]
    cdef Quaternion rot = Quaternion(rotation.w, rotation.x, rotation.y, rotation.z)
    with nogil:
        apply_rotation_cpp(verts_ptr, vert_count, rot) 

def align_to_axes_batch(list selected_objects):
    start_prep = time.perf_counter()
    cdef cnp.ndarray all_verts
    cdef cnp.ndarray all_edges

    cdef list all_vert_counts = []
    cdef list all_edge_counts = []
    cdef list batch_items = []
    cdef list all_original_rots = []  # flat list of tuples
    
    cdef list rots
    cdef list trans
    
    # Helper function to get all mesh objects recursively
    def get_all_mesh_objects(object coll):
        cdef list objects = []
        cdef object obj
        cdef object child
        for obj in coll.objects:
            if obj.type == 'MESH':
                objects.append(obj)
        for child in coll.children:
            objects.extend(get_all_mesh_objects(child))
        return objects
    
    # Helper function to find top-level collection
    def find_top_coll(object coll, object scene_coll):
        # Since no .parent, we use a pre-built map
        return coll_to_top.get(coll, None)

    # Build map of coll to top_coll
    cdef dict coll_to_top = {}
    cdef object top_coll
    for top_coll in bpy.context.scene.collection.children:
        coll_to_top[top_coll] = top_coll
        # Recursive function to build map
        def build_top_map(object current_coll, object current_top):
            for child in current_coll.children:
                coll_to_top[child] = current_top
                build_top_map(child, current_top)
        build_top_map(top_coll, top_coll)

    
    # First pass: Collect groups and individuals
    cdef object scene_coll = bpy.context.scene.collection
    cdef dict obj_groups = {}  # top_coll -> list of all mesh objs
    cdef dict mesh_cache = {}
    cdef list individual_objects = []
    cdef int total_verts = 0
    cdef int total_edges = 0
    cdef object obj
    cdef object coll

    

    cdef object group_coll
    for obj in selected_objects:
        group_coll = None
        if obj.users_collection:
            coll = obj.users_collection[0]
            if coll != scene_coll:
                top_coll = find_top_coll(coll, scene_coll)
                if top_coll not in mesh_cache:
                    mesh_cache[top_coll] = get_all_mesh_objects(top_coll)
                if len(mesh_cache[top_coll]) > 1:
                    group_coll = top_coll
        
        if group_coll is None:
            individual_objects.append(obj)
            if obj.type == 'MESH':
                total_verts += len(obj.data.vertices)
                total_edges += len(obj.data.edges)
        else:
            if group_coll not in obj_groups:
                obj_groups[group_coll] = mesh_cache[group_coll]
                for o in obj_groups[group_coll]:
                    total_verts += len(o.data.vertices)
                    total_edges += len(o.data.edges)

    all_verts = np.empty((total_verts * 3), dtype=np.float32)
    all_edges = np.empty((total_edges * 2), dtype=np.uint32)

    cdef uint32_t curr_all_verts_offset = 0
    cdef uint32_t curr_all_edges_offset = 0

    all_vert_counts = []
    all_edge_counts = []

    end_prep = time.perf_counter()
    print(f"Preparation time elapsed: {(end_prep - start_prep) * 1000:.2f}ms")

    start_collections = time.perf_counter()
    # Process collections
    cdef list group
    cdef object mesh
    cdef object first_obj

    cdef cnp.ndarray group_vert_counts
    cdef cnp.ndarray group_edge_counts
    cdef uint32_t[::1] vert_counts_view
    cdef uint32_t[::1] edge_counts_view
    cdef uint32_t *vert_counts_ptr
    cdef uint32_t *edge_counts_ptr

    cdef uint32_t group_vert_count
    cdef uint32_t group_edge_count

    cdef cnp.ndarray offsets_array
    cdef cnp.ndarray rotations_array
    cdef float[::1] offsets_view
    cdef float[::1] rotations_view
    cdef Vec3* offsets_ptr
    cdef Quaternion* rotations_ptr
    
    cdef uint32_t num_objects

    cdef float[::1] group_verts_view
    cdef uint32_t[::1] group_edges_view
    cdef uVec2i* group_edges_slice_ptr
    cdef Vec3* group_verts_slice_ptr

    cdef uint32_t curr_group_vert_offset = 0
    cdef uint32_t curr_group_edge_offset = 0

    for group in obj_groups.values():
        
        curr_group_vert_offset = 0
        curr_group_edge_offset = 0

        num_objects = len(group)

        # Collect per object data
        group_vert_counts = np.fromiter(
            (len(obj.data.vertices) for obj in group),
            dtype=np.uint32,
            count = num_objects
        )
        vert_counts_view = group_vert_counts
        vert_counts_ptr = &vert_counts_view[0]

        group_edge_counts = np.fromiter(
            (len(obj.data.edges) for obj in group),
            dtype=np.uint32,
            count = num_objects
        )
        edge_counts_view = group_edge_counts
        edge_counts_ptr = &edge_counts_view[0]


        # Collect group aggregate data
        group_vert_count = sum(len(obj.data.vertices) for obj in group)
        group_edge_count = sum(len(obj.data.edges) for obj in group)

        group_verts_slice = all_verts[curr_all_verts_offset:curr_all_verts_offset + group_vert_count * 3]
        group_edges_slice = all_edges[curr_all_edges_offset:curr_all_edges_offset + group_edge_count * 2]

        curr_all_verts_offset += group_vert_count * 3
        curr_all_edges_offset += group_edge_count * 2

        # Fill vertex and edge data for group
        for obj in group:
            obj.rotation_mode = 'QUATERNION'

            mesh = obj.data
            obj_vert_count = len(mesh.vertices)
            verts_slice = group_verts_slice[curr_group_vert_offset:curr_group_vert_offset + obj_vert_count * 3]
            mesh.vertices.foreach_get("co", verts_slice)

            obj_edge_count = len(mesh.edges)
            edges_slice = group_edges_slice[curr_group_edge_offset:curr_group_edge_offset + obj_edge_count * 2]
            mesh.edges.foreach_get("vertices", edges_slice)

            curr_group_vert_offset += obj_vert_count * 3
            curr_group_edge_offset += obj_edge_count * 2

        # Compute offsets and rotations for collection
        first_obj = group[0]
        
        # For rotations (flatten w, x, y, z into scalars)
        rotations_array = np.fromiter(
            (component for obj in group for component in (obj.rotation_quaternion.w, obj.rotation_quaternion.x, obj.rotation_quaternion.y, obj.rotation_quaternion.z)),
            dtype=np.float32,
            count=num_objects * 4,
        )
        rotations_view = rotations_array
        rotations_ptr = <Quaternion*> &rotations_view[0]

        # For offsets (flatten x, y, z into scalars)
        offsets_array = np.fromiter(
            (component for obj in group for component in (obj.location - first_obj.location).to_tuple()),
            dtype=np.float32,
            count=num_objects * 3,
        )
        offsets_view = offsets_array
        offsets_ptr = <Vec3*> &offsets_view[0]

        group_verts_view = group_verts_slice
        group_edges_view = group_edges_slice

        group_edges_slice_ptr = <uVec2i*>&group_edges_view[0]
        group_verts_slice_ptr = <Vec3*> &group_verts_view[0]

        # Group objects in collection
        group_objects_cpp(group_verts_slice_ptr, group_edges_slice_ptr, vert_counts_ptr, edge_counts_ptr, offsets_ptr, rotations_ptr, num_objects)

        # Add to overall buffers
        all_vert_counts.append(group_vert_count)
        all_edge_counts.append(group_edge_count)

        # Record batch items and original rotations
        batch_items.append(group)
        for obj in group:
            all_original_rots.append(obj.rotation_quaternion)

    end_collections = time.perf_counter()
    print(f"Collection processing time elapsed: {(end_collections - start_collections) * 1000:.2f}ms")

    start_individual = time.perf_counter()
    # Process individual objects
    for obj in individual_objects:
        obj.rotation_mode = 'QUATERNION'
        mesh = obj.data
        group_vert_count = len(mesh.vertices)
        if group_vert_count == 0:
            continue
        
        group_verts_slice = all_verts[curr_all_verts_offset:curr_all_verts_offset + group_vert_count * 3]
        mesh.vertices.foreach_get("co", group_verts_slice)
        
        group_edge_count = len(mesh.edges)
        group_edges_slice = all_edges[curr_all_edges_offset:curr_all_edges_offset + group_edge_count * 2]
        mesh.edges.foreach_get("vertices", group_edges_slice)
        
        curr_all_verts_offset += group_vert_count * 3
        curr_all_edges_offset += group_edge_count * 2
        
        all_vert_counts.append(group_vert_count)
        all_edge_counts.append(group_edge_count)
        batch_items.append([obj])
        all_original_rots.append(obj.rotation_quaternion)

        apply_rotation(group_verts_slice, group_vert_count, obj.rotation_quaternion)
    
    end_individual = time.perf_counter()
    print(f"Individual processing time elapsed: {(end_individual - start_individual) * 1000:.2f}ms")

    start_alignment = time.perf_counter()

    if all_verts.size > 0:
        
        # Call batched C++ function for all
        rots, trans = align_min_bounds(all_verts, all_edges, all_vert_counts, all_edge_counts)

        end_alignment = time.perf_counter()
        print(f"Alignment time elapsed: {(end_alignment - start_alignment) * 1000:.2f}ms")
        
        return rots, trans, batch_items, all_original_rots
    else:
        end_alignment = time.perf_counter()
        print(f"Alignment time elapsed: {(end_alignment - start_alignment) * 1000:.2f}ms")
        return [], [], [], []