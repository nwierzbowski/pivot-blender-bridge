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

import elbo_sdk_rust as engine
import json
from libc.stdint cimport uint32_t
from libc.string cimport memcpy, memset
from .timer_manager import timers
from . import id_manager

def create_data_arrays(list mesh_groups, list group_names, list collections, list surface_contexts):
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
    timers.start("rust.makeshm")
    # Prepare shared memory using the per-object counts and group data so finalize needs no args
    # print(f"[Pivot] Selected {len(collections)} collections for SHM allocation. Names: {group_names}")

    shm_context = engine.prepare_standardize_groups(
        vert_counts_list,
        edge_counts_list,
        object_counts_list,
        group_names,
        surface_contexts,
        id_manager.get_or_create_asset_uuid(collections)
    )
    print("create_data_arrays.make_shm: ", timers.stop("rust.makeshm"), "ms")
    timers.reset("rust.makeshm")

    cdef uint32_t v_cursor
    cdef uint32_t e_cursor

    # Typed memoryviews for zero-copy writes
    cdef float[::1] trans_mv
    cdef unsigned char[::1] names_mv
    cdef unsigned char[::1] uuids_mv
    cdef uint32_t[::1] vcount_mv
    cdef uint32_t[::1] ecount_mv
    cdef float[::1] vpool_mv
    cdef uint32_t[::1] epool_mv
    cdef object vcount_cast
    cdef object ecount_cast
    cdef object vpool_cast
    cdef object epool_cast
    cdef object trans_cast
    cdef object names_cast
    cdef object uuids_cast
    cdef object mat
    cdef Py_ssize_t obj_index
    cdef bytes name_bytes
    cdef Py_ssize_t name_len
    cdef const unsigned char* name_ptr
    cdef float *outp
    cdef bytes uuid_seq
    cdef const unsigned char *uuid_ptr

    timers.start("data_arrays.loop")
    for i, group in enumerate(mesh_groups):
        v_cursor = 0
        e_cursor = 0
        idx_trans = 0

        verts_shm, edges_shm, transforms_shm, vcounts_shm, ecounts_shm, object_names_shm, uuids_shm = shm_context.buffers(i)

        # Rust exposes raw u8 buffers; cast to typed views here.
        # Use Python's memoryview(...) constructor here (not a Cython type-cast) so we correctly
        # wrap any buffer-exporting object returned from Rust.
        vpool_cast = memoryview(verts_shm).cast('f')
        epool_cast = memoryview(edges_shm).cast('I')
        trans_cast = memoryview(transforms_shm).cast('f')
        vcount_cast = memoryview(vcounts_shm).cast('I')
        ecount_cast = memoryview(ecounts_shm).cast('I')
        names_cast = memoryview(object_names_shm).cast('B')
        uuids_cast = memoryview(uuids_shm).cast('B')

        vpool_mv = vpool_cast
        epool_mv = epool_cast
        trans_mv = trans_cast
        vcount_mv = vcount_cast
        ecount_mv = ecount_cast
        names_mv = names_cast
        uuids_mv = uuids_cast
        
        for obj_index in range(len(group)):
            obj, mesh, verts, edges = group[obj_index]
            vcount_mv[obj_index] = v_cursor
            ecount_mv[obj_index] = e_cursor
            uuid_bytes = id_manager.get_or_create_obj_uuid(obj.original)
            uuid_seq = bytes(uuid_bytes)
            if len(uuid_seq) != 16:
                raise ValueError(f"pivot uuid must be 16 bytes but got {len(uuid_seq)}")
            uuid_ptr = <const unsigned char *>uuid_seq
            memcpy(&uuids_mv[obj_index * 16], uuid_ptr, 16)

            name_bytes = obj.name.encode('utf-8')
            name_len = len(name_bytes)
            if name_len > 64:
                name_len = 64
            name_ptr = <const unsigned char*>name_bytes
            memcpy(&names_mv[obj_index * 64], name_ptr, name_len)
            if name_len < 64:
                memset(&names_mv[obj_index * 64 + name_len], 0, 64 - name_len)

            mat = obj.matrix_world
            # Fallback: cache rows to reduce repeated Python lookups.
            r0 = mat[0]
            r1 = mat[1]
            r2 = mat[2]
            r3 = mat[3]
            outp = &trans_mv[idx_trans]
            outp[0] = <float>r0[0]
            outp[1] = <float>r1[0]
            outp[2] = <float>r2[0]
            outp[3] = <float>r3[0]
            outp[4] = <float>r0[1]
            outp[5] = <float>r1[1]
            outp[6] = <float>r2[1]
            outp[7] = <float>r3[1]
            outp[8] = <float>r0[2]
            outp[9] = <float>r1[2]
            outp[10] = <float>r2[2]
            outp[11] = <float>r3[2]
            outp[12] = <float>r0[3]
            outp[13] = <float>r1[3]
            outp[14] = <float>r2[3]
            outp[15] = <float>r3[3]

            idx_trans += 16

            timers.start("create_data_arrays.loop.foreach_get_verts")
            mesh.attributes["position"].data.foreach_get("vector", vpool_mv[v_cursor * 3:v_cursor * 3 + len(verts) * 3])
            v_cursor += len(verts)
            timers.stop("create_data_arrays.loop.foreach_get_verts")

            timers.start("create_data_arrays.loop.foreach_get_edges")
            mesh.edges.foreach_get("vertices", epool_mv[e_cursor * 2:e_cursor * 2 + len(edges) * 2])
            e_cursor += len(edges)
            timers.stop("create_data_arrays.loop.foreach_get_edges")

        # Sentinel totals (bases length = object_count + 1)
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

    
    return final_response