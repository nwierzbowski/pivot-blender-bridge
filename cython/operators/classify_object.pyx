# classify_object.pyx - Main classification operator

from libc.stdint cimport uint32_t
from libc.stddef cimport size_t
from mathutils import Quaternion, Vector

import numpy as np
import time
import bpy

from . import selection_utils, shm_utils, transform_utils

def classify_and_apply_objects(list selected_objects, collection):
    cdef double start_prep = time.perf_counter()
    cdef double end_prep, start_processing, end_processing, start_alignment, end_alignment
    cdef double classify_send_start, classify_send_end, face_prep_start, face_prep_end
    cdef double faces_send_start, faces_send_end, classify_wait_start, classify_wait_end
    cdef double faces_wait_start, faces_wait_end, start_apply, end_apply

    cdef list all_original_rots = []

    # Collect selection into groups and individuals and precompute totals
    cdef list mesh_groups
    cdef list parent_groups
    cdef list full_groups
    cdef list group_names
    cdef int total_verts
    cdef int total_edges
    cdef int total_objects
    cdef uint32_t[::1] vert_counts_mv
    cdef uint32_t[::1] edge_counts_mv
    cdef uint32_t[::1] object_counts_mv
    cdef list group
    mesh_groups, parent_groups, full_groups, group_names, total_verts, total_edges, total_objects = selection_utils.aggregate_object_groups(selected_objects, collection)

    # Create shared memory segments and numpy arrays for verts/edges only
    shm_objects, shm_names, count_memory_views = shm_utils.create_data_arrays(total_verts, total_edges, total_objects, mesh_groups)

    verts_shm_name, edges_shm_name, rotations_shm_name, scales_shm_name, offsets_shm_name = shm_names
    vert_counts_mv, edge_counts_mv, object_counts_mv, offsets_mv = count_memory_views

    end_prep = time.perf_counter()
    print(f"Preparation time elapsed: {(end_prep - start_prep) * 1000:.2f}ms")

    start_processing = time.perf_counter()

    cdef size_t current_offset_idx = 0
    cdef size_t group_size
    cdef size_t group_offset_size
    cdef float[::1] group_offsets_slice
    cdef object first_obj

    cdef Py_ssize_t group_idx
    cdef list all_parent_offsets = []

    for group_idx in range(len(parent_groups)):
        group = parent_groups[group_idx]
        mesh_group = mesh_groups[group_idx]
        group_size = len(mesh_group)
        group_offset_size = group_size * 3  # 3 floats per object (x,y,z)
        group_offsets_slice = offsets_mv[current_offset_idx:current_offset_idx + group_offset_size]
        
        parent_offsets = transform_utils.compute_offset_transforms(group, mesh_group, group_offsets_slice)
        all_parent_offsets.append(parent_offsets)

        for obj in group:
            obj.rotation_mode = 'QUATERNION' 
            all_original_rots.append(obj.rotation_quaternion)
        
        current_offset_idx += group_offset_size

    end_processing = time.perf_counter()
    print(f"Block processing time elapsed: {(end_processing - start_processing) * 1000:.2f}ms")

    start_alignment = time.perf_counter()

    # Send classify op to engine (without faces for pipelining)
    cdef dict command = {
        "id": 1,
        "op": "classify",
        "shm_verts": verts_shm_name,
        "shm_edges": edges_shm_name,
        "shm_rotations": rotations_shm_name,
        "shm_scales": scales_shm_name,
        "shm_offsets": offsets_shm_name,
        "vert_counts": list(vert_counts_mv),
        "edge_counts": list(edge_counts_mv),
        "object_counts": list(object_counts_mv),
        "group_names": group_names
    }

    from splatter.engine import get_engine_communicator
    from splatter.engine_state import set_engine_parent_groups
    engine = get_engine_communicator()
    
    # Send classify command asynchronously (don't wait for response yet)
    classify_send_start = time.perf_counter()
    engine.send_command_async(command)
    classify_send_end = time.perf_counter()
    print(f"Classify command sent: {(classify_send_end - classify_send_start) * 1000:.2f}ms")
    
    # Start preparing face data while classify command is being processed
    face_prep_start = time.perf_counter()
    
    # Prepare face data asynchronously while engine processes
    face_shm_objects, face_shm_names, face_counts_mv, face_sizes_mv, face_vert_counts_mv, total_faces_count, total_faces = shm_utils.prepare_face_data(total_objects, mesh_groups)
    faces_shm_name, face_sizes_shm_name = face_shm_names
    
    face_prep_end = time.perf_counter()
    print(f"Face preparation time: {(face_prep_end - face_prep_start) * 1000:.2f}ms")
    
    # Send face data to engine asynchronously (while classify is still processing)
    if total_faces > 0:  # Only send if there are faces to send
        faces_send_start = time.perf_counter()
        faces_command = {
            "id": 2,
            "op": "send_faces",
            "shm_faces": faces_shm_name,
            "shm_face_sizes": face_sizes_shm_name,
            "face_counts": list(face_counts_mv),  # All face counts for all objects
            "group_names": group_names,  # Group names for association
            "object_counts": list(object_counts_mv)  # Object counts per group to split face data
        }
        
        
    
    # Now wait for classify response (this is where we block)
    classify_wait_start = time.perf_counter()
    final_response = engine.wait_for_response(1)  # Wait for response with id=1
    classify_wait_end = time.perf_counter()
    print(f"Classify response received: {(classify_wait_end - classify_wait_start) * 1000:.2f}ms")
    
    # If we sent faces, wait for that response too before closing shared memory
    if total_faces > 0:
        engine.send_command_async(faces_command)
        faces_send_end = time.perf_counter()
        print(f"Faces command sent: {(faces_send_end - faces_send_start) * 1000:.2f}ms")
        faces_wait_start = time.perf_counter()
        faces_response = engine.wait_for_response(2)  # Wait for response with id=2
        faces_wait_end = time.perf_counter()
        print(f"Faces response received: {(faces_wait_end - faces_wait_start) * 1000:.2f}ms")
    
    # Now it's safe to close face shared memory handles
    for shm in face_shm_objects:
        shm.close()
    
    cdef dict groups = final_response["groups"]
    cdef list rots = [Quaternion(groups[name]["rot"]) for name in group_names]
    cdef list surface_type = [groups[name]["surface_type"] for name in group_names]
    cdef list origin = [tuple(groups[name]["origin"]) for name in group_names]

    # Compute new locations for each object using Cython rotation of offsets, then add ref location
    cdef list locs = []
    cdef Py_ssize_t i, j
    cdef float rx, ry, rz
    cdef list parent_offsets_mv
    cdef list all_rotated_offsets = []

    for i in range(len(parent_groups)):
        # Rotate this group's offsets in-place using numpy for speed
        group = parent_groups[i]
        group_size = <uint32_t> len(group)
        parent_offsets_mv = all_parent_offsets[i]
        rot_matrix = np.array(rots[i].to_matrix())
        offsets_array = np.asarray(parent_offsets_mv).reshape(group_size, 3)
        rotated_offsets = offsets_array @ rot_matrix.T
        rotated_flat = rotated_offsets.flatten()

        # Convert to list for storage
        rotated_offsets_list = [(rotated_flat[j * 3], rotated_flat[j * 3 + 1], rotated_flat[j * 3 + 2]) for j in range(group_size)]
        all_rotated_offsets.append(rotated_offsets_list)

        # Add the reference location to each rotated offset and collect as tuples
        ref_vec = parent_groups[i][0].matrix_world.translation
        rx = <float> ref_vec.x
        ry = <float> ref_vec.y
        rz = <float> ref_vec.z
        for j in range(len(group)):
            locs.append((rx + rotated_flat[j * 3], ry + rotated_flat[j * 3 + 1], rz + rotated_flat[j * 3 + 2]))

    # Store parent groups globally for later positioning work
    cdef dict parent_groups_dict = {group_names[i]: {'objects': parent_groups[i], 'offsets': all_rotated_offsets[i]} for i in range(len(group_names))}
    set_engine_parent_groups(parent_groups_dict)

    # Close shared memory handles in parent process; let engine manage unlinking since it may hold longer
    for shm in shm_objects:
        shm.close()

    end_alignment = time.perf_counter()
    print(f"Alignment time elapsed: {(end_alignment - start_alignment) * 1000:.2f}ms")

    # Apply results
    start_apply = time.perf_counter()
    cdef int obj_idx = 0
    cdef tuple loc
    for i, group in enumerate(parent_groups):
        delta_quat = rots[i]
        first_obj = group[0]
        cursor_loc = Vector(origin[i]) + first_obj.location
        bpy.context.scene.cursor.location = cursor_loc

        for obj in group:
            local_quat = all_original_rots[obj_idx]
            loc = locs[obj_idx]
            
            obj.rotation_quaternion = (delta_quat @ local_quat).normalized()
            obj.location = Vector(loc)
            obj_idx += 1

    for i, group in enumerate(full_groups):
        surface_type_value = surface_type[i]
        group_name = group_names[i]
        
        # Since the engine is the source of truth, update each object without sending commands back to engine
        if group:  # Make sure group is not empty
            from splatter.property_manager import get_property_manager
            prop_manager = get_property_manager()
            
            # Set group names and surface types for all objects in the group
            for obj in group:
                if hasattr(obj, "classification"):
                    prop_manager.set_group_name(obj, group_name)
                    prop_manager.set_attribute(obj, 'surface_type', surface_type_value, update_group=False, update_engine=False)
    
    end_apply = time.perf_counter()
    print(f"Application time elapsed: {(end_apply - start_apply) * 1000:.2f}ms")