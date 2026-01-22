# Copyright (C) 2025 [Nicholas Wierzbowski/Elbo Studio]

# This file is part of the Pivot Bridge for Blender.

# The Pivot Bridge for Blender is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, see <https://www.gnu.org/licenses>.

import numpy as np
cimport numpy as cnp
import elbo_sdk_rust as engine
import json
from mathutils import Matrix, Vector
from libc.stdint cimport uint32_t
from libc.stddef cimport size_t
from .timer_manager import timers

def create_data_arrays(list mesh_groups, list pivots, bint is_group_mode, list group_names, list surface_contexts):
    # Build counts and object names without generators to avoid closures
    cdef list vert_counts_list = []
    cdef list edge_counts_list = []
    cdef list object_counts_list = []
    cdef list object_names_list = []
    cdef list group
    cdef object obj
    cdef object mesh

    timers.start("create_data_arrays.totals")
    for group in mesh_groups:
        object_counts_list.append(len(group))
        group_vert_total = 0
        group_edge_total = 0
        for i, (obj, mesh, verts, edges) in enumerate(group):
            object_names_list.append(obj.name)
            group_vert_total += len(verts)
            group_edge_total += len(edges)
        vert_counts_list.append(group_vert_total)
        edge_counts_list.append(group_edge_total)
    print("create_data_arrays.totals: ", timers.stop("create_data_arrays.totals"), "ms")
    timers.reset("create_data_arrays.totals")

    # Decide whether to reuse the caller-supplied group names or fall back to the raw object names
    cdef list effective_group_names = group_names if is_group_mode else object_names_list
    timers.start("rust.makeshm")
    # Prepare shared memory using the per-object counts and group data so finalize needs no args
    shm_context = engine.prepare_standardize_groups(
        vert_counts_list,
        edge_counts_list,
        object_counts_list,
        effective_group_names,
        surface_contexts,
    )
    print("create_data_arrays.make_shm: ", timers.stop("rust.makeshm"), "ms")
    timers.reset("rust.makeshm")

    cdef size_t idx_rot = 0
    cdef size_t idx_scale = 0
    cdef size_t idx_offset = 0
    cdef object quat
    cdef object scale_vec
    
    cdef object pivot_obj
    cdef object pivot_matrix_world
    cdef object pivot_matrix_inv
    cdef object obj_local_matrix
    cdef object local_translation
    cdef object trans_vec
    cdef uint32_t v_cursor
    cdef uint32_t e_cursor

    cdef cnp.ndarray group_verts
    cdef cnp.ndarray group_edges

    # Typed memoryviews for zero-copy writes
    cdef float[::1] rot_mv
    cdef float[::1] scale_mv
    cdef float[::1] off_mv
    cdef uint32_t[::1] vcount_mv
    cdef uint32_t[::1] ecount_mv
    cdef float[::1] vpool_mv
    cdef uint32_t[::1] epool_mv
    cdef object rot_cast
    cdef object scale_cast
    cdef object off_cast
    cdef object vcount_cast
    cdef object ecount_cast
    cdef object vpool_cast
    cdef object epool_cast

    timers.start("data_arrays.loop")
    for i, group in enumerate(mesh_groups):
        v_cursor = 0
        e_cursor = 0
        idx_rot = 0
        idx_scale = 0
        idx_offset = 0

        verts_shm, edges_shm, rotations_shm, scales_shm, offsets_shm, vcounts_shm, ecounts_shm = shm_context.buffers(i)

        # group_verts = np.ndarray((vert_counts_list[i] * 3,), dtype=np.float32, buffer=verts_shm)
        # group_edges = np.ndarray((edge_counts_list[i] * 2,), dtype=np.uint32, buffer=edges_shm)

        # Rust exposes raw u8 buffers; cast to typed views here.
        vpool_cast = (<memoryview>verts_shm).cast('f')
        epool_cast = (<memoryview>edges_shm).cast('I')
        rot_cast = (<memoryview>rotations_shm).cast('f')
        scale_cast = (<memoryview>scales_shm).cast('f')
        off_cast = (<memoryview>offsets_shm).cast('f')
        vcount_cast = (<memoryview>vcounts_shm).cast('I')
        ecount_cast = (<memoryview>ecounts_shm).cast('I')

        vpool_mv = vpool_cast
        epool_mv = epool_cast
        rot_mv = rot_cast
        scale_mv = scale_cast
        off_mv = off_cast
        vcount_mv = vcount_cast
        ecount_mv = ecount_cast


        pivot_obj = None
        if pivots is not None and i < len(pivots):
            pivot_obj = pivots[i]
        if pivot_obj is not None:
            pivot_matrix_world = pivot_obj.matrix_world.copy()
            pivot_matrix_inv = pivot_matrix_world.inverted()
            pivot_basis_inv = pivot_matrix_inv.to_3x3()
            use_pivot_transform = True
        else:
            pivot_matrix_inv = Matrix.Identity(4)
            pivot_basis_inv = Matrix.Identity(3)
            use_pivot_transform = False



        for i, (obj, mesh, verts, edges) in enumerate(group):
            vcount_mv[i] = v_cursor
            ecount_mv[i] = e_cursor

            if use_pivot_transform:
                obj_local_matrix = pivot_matrix_inv @ obj.matrix_world
                quat = obj_local_matrix.to_3x3().to_quaternion()
                trans_vec = obj.matrix_world.translation - pivot_obj.matrix_world.translation
                local_translation = pivot_basis_inv @ trans_vec
            else:
                quat = obj.matrix_world.to_3x3().to_quaternion()
                local_translation = Vector((0.0, 0.0, 0.0))


            rot_mv[idx_rot] = quat.w
            rot_mv[idx_rot + 1] = quat.x
            rot_mv[idx_rot + 2] = quat.y
            rot_mv[idx_rot + 3] = quat.z

            scale_vec = obj.matrix_world.to_3x3().to_scale()
            scale_mv[idx_scale] = scale_vec.x
            scale_mv[idx_scale + 1] = scale_vec.y
            scale_mv[idx_scale + 2] = scale_vec.z

            off_mv[idx_offset] = local_translation.x
            off_mv[idx_offset + 1] = local_translation.y
            off_mv[idx_offset + 2] = local_translation.z

            idx_rot += 4
            idx_scale += 3
            idx_offset += 3

            timers.start("create_data_arrays.loop.foreach_get_verts")
            if len(verts) > 0:
                mesh.attributes["position"].data.foreach_get("vector", vpool_mv[v_cursor * 3:v_cursor * 3 + len(verts) * 3])
                v_cursor += len(verts)
            timers.stop("create_data_arrays.loop.foreach_get_verts")

            timers.start("create_data_arrays.loop.foreach_get_edges")
            if len(edges) > 0:
                mesh.edges.foreach_get("vertices", epool_mv[e_cursor * 2:e_cursor * 2 + len(edges) * 2])
                e_cursor += len(edges)
            timers.stop("create_data_arrays.loop.foreach_get_edges")

        vcount_mv[len(group)] = v_cursor
        ecount_mv[len(group)] = e_cursor

    print("create_data_arrays.loop.foreach_get_verts: ", timers.get_elapsed_ms("create_data_arrays.loop.foreach_get_verts"), "ms")
    timers.reset("create_data_arrays.loop.foreach_get_verts")

    print("create_data_arrays.loop.foreach_get_edges: ", timers.get_elapsed_ms("create_data_arrays.loop.foreach_get_edges"), "ms")
    timers.reset("create_data_arrays.loop.foreach_get_edges")


    print ("create_data_arrays.loop: ", timers.stop("data_arrays.loop"), "ms")
    timers.reset("data_arrays.loop")

    timers.start("create_data_arrays.finalize")
    final_json = shm_context.finalize()
    final_response = json.loads('{"ok": true }')
    
    print("create_data_arrays.finalize: ", timers.stop("create_data_arrays.finalize"), "ms")
    timers.reset("create_data_arrays.finalize")

    timers.start("set_origin_selected_objects.underhead")
    return final_response


# def prepare_face_data(uint32_t total_objects, list mesh_groups):
#     """Prepare face data for sending to engine after initial classification."""
#     cdef uint32_t total_faces_count = 0
#     cdef uint32_t total_face_vertices = 0
#     cdef size_t expected_objects = 0
#     cdef list group
#     cdef object obj
#     cdef uint32_t obj_face_count
#     cdef uint32_t obj_vertex_count
#     cdef cnp.ndarray[cnp.uint32_t, ndim=1] face_sizes_slice
#     cdef cnp.ndarray[cnp.uint32_t, ndim=1] shm_face_sizes_buf = None
#     cdef cnp.ndarray[cnp.uint32_t, ndim=1] shm_faces_buf = None
#     cdef cnp.ndarray[cnp.uint32_t, ndim=1] face_counts = None
#     cdef cnp.ndarray[cnp.uint32_t, ndim=1] face_vert_counts = None
#     cdef uint32_t[::1] face_sizes_slice_view
#     cdef uint32_t[::1] face_counts_mv
#     cdef uint32_t[::1] face_sizes_mv
#     cdef uint32_t[::1] face_vert_counts_mv
#     cdef uint32_t[::1] face_vert_counts_view
#     cdef uint32_t face_sizes_offset = 0
#     cdef uint32_t obj_idx = 0
#     cdef uint32_t faces_offset = 0
#     cdef size_t faces_size = 0
#     cdef tuple shm_objects
#     cdef tuple shm_names
#     cdef str faces_shm_name = ""
#     cdef str face_sizes_shm_name = ""
#     cdef object faces_shm = None
#     cdef object face_sizes_shm = None
#     depsgraph = bpy.context.evaluated_depsgraph_get()

#     # First pass: gather totals and validate counts
#     for group in mesh_groups:
#         expected_objects += len(group)
#         for obj in group:
#             eval_obj = obj.evaluated_get(depsgraph)
#             eval_mesh = eval_obj.data
#             total_faces_count += len(eval_mesh.polygons)

#     if expected_objects != total_objects:
#         raise ValueError(f"prepare_face_data: expected {expected_objects} objects, received {total_objects}")

#     # Early exit when no faces are present
#     if total_faces_count == 0:
#         face_counts = np.zeros(total_objects, dtype=np.uint32)
#         face_vert_counts = np.zeros(total_objects, dtype=np.uint32)
#         shm_face_sizes_buf = np.zeros(0, dtype=np.uint32)

#         face_counts_mv = face_counts
#         face_sizes_mv = shm_face_sizes_buf
#         face_vert_counts_mv = face_vert_counts

#         return (), ("", ""), face_counts_mv, face_sizes_mv, face_vert_counts_mv, 0, 0

#     cdef str uid_faces

#     try:
#         face_sizes_shm, face_sizes_shm_name, uid_faces = shm_manager.create_face_sizes_segment(total_faces_count)
#         shm_face_sizes_buf = np.ndarray((total_faces_count,), dtype=np.uint32, buffer=face_sizes_shm.buf)

#         face_counts = np.empty(total_objects, dtype=np.uint32)
#         face_vert_counts = np.empty(total_objects, dtype=np.uint32)

#         face_sizes_offset = 0
#         obj_idx = 0

#         for group in mesh_groups:
#             for obj in group:
#                 eval_obj = obj.evaluated_get(depsgraph)
#                 eval_mesh = eval_obj.data
#                 obj_face_count = <uint32_t>len(eval_mesh.polygons)
#                 face_counts[obj_idx] = obj_face_count

#                 if obj_face_count > 0:
#                     face_sizes_slice = shm_face_sizes_buf[face_sizes_offset:face_sizes_offset + obj_face_count]
#                     eval_mesh.polygons.foreach_get('loop_total', face_sizes_slice)

#                     obj_vertex_count = 0
#                     face_sizes_slice_view = face_sizes_slice
#                     for i in range(obj_face_count):
#                         obj_vertex_count += face_sizes_slice_view[i]

#                     face_vert_counts[obj_idx] = obj_vertex_count
#                     total_face_vertices += obj_vertex_count
#                 else:
#                     face_vert_counts[obj_idx] = 0

#                 face_sizes_offset += obj_face_count
#                 obj_idx += 1

#         if total_face_vertices == 0:
#             raise ValueError("prepare_face_data: collected faces but no vertex indices recorded")

#         faces_shm, faces_shm_name = shm_manager.create_faces_segment(total_face_vertices, uid_faces)
#         shm_faces_buf = np.ndarray((total_face_vertices,), dtype=np.uint32, buffer=faces_shm.buf)

#         faces_offset = 0
#         obj_idx = 0
#         face_vert_counts_view = face_vert_counts

#         for group in mesh_groups:
#             for obj in group:
#                 eval_obj = obj.evaluated_get(depsgraph)
#                 eval_mesh = eval_obj.data
#                 obj_vertex_count = face_vert_counts_view[obj_idx]
#                 if obj_vertex_count > 0:
#                     eval_mesh.polygons.foreach_get("vertices", shm_faces_buf[faces_offset:faces_offset + obj_vertex_count])
#                     faces_offset += obj_vertex_count
#                 obj_idx += 1

#         face_counts_mv = face_counts
#         face_sizes_mv = shm_face_sizes_buf
#         face_vert_counts_mv = face_vert_counts_view

#         shm_objects = (faces_shm, face_sizes_shm)
#         shm_names = (faces_shm_name, face_sizes_shm_name)

#         return shm_objects, shm_names, face_counts_mv, face_sizes_mv, face_vert_counts_mv, total_faces_count, total_face_vertices

#     except Exception:
#         if faces_shm is not None:
#             try:
#                 pass
#             except Exception:
#                 pass
#             faces_shm.close()
#             faces_shm.unlink()
#         if face_sizes_shm is not None:
#             try:
#                 pass
#             except Exception:
#                 pass
#             face_sizes_shm.close()
#             face_sizes_shm.unlink()
#         raise
