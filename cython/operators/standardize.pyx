# classify_object.pyx - Classifies and applies transformations to Blender objects.
#
# This module handles:
# - Communicating with the C++ engine to compute object classifications
# - Computing and applying new world-space transforms based on engine output
# - Managing collection hierarchy for surface type classification (Pro edition)

from libc.stddef cimport size_t
from mathutils import Quaternion, Vector, Matrix

import numpy as np
import bpy

from . import selection_utils, shm_utils, transform_utils, edition_utils, group_manager
from pivot import engine_state
from pivot.engine import get_engine_communicator

# Collection metadata keys
GROUP_COLLECTION_PROP = "pivot_group_name"
CLASSIFICATION_ROOT_COLLECTION_NAME = "Pivot"
CLASSIFICATION_COLLECTION_PROP = "pivot_surface_type"



def _setup_pivots_for_groups_return_empties(parent_groups, group_names, origins, first_world_locs):
    """Set up one pivot empty per group with smart empty detection/creation."""
    pivots = []
    for i, parent_group in enumerate(parent_groups):
        target_origin = Vector(origins[i]) + first_world_locs[i]
        empty = _get_or_create_pivot_empty(parent_group, group_names[i], target_origin)
        pivots.append(empty)
    return pivots


def _get_or_create_pivot_empty(parent_group, group_name, target_origin):
    """
    Get or create a single pivot empty for the group.
    - If group's collection has exactly one empty, reuse it
    - If group's collection has no empties, create one
    - If group's collection has multiple empties, create a new one and parent existing empties to it
    Only parent the parent objects (from parent_group) to the pivot; children inherit automatically.
    Returns: the pivot empty (which is NOT added to parent_group)
    """
    # Get the collection containing the first object
    group_collection = parent_group[0].users_collection[0] if parent_group[0].users_collection else bpy.context.scene.collection
    
    # Find all empties in the collection
    empties_in_collection = [obj for obj in group_collection.objects if obj.type == 'EMPTY']
    
    # Determine which empty to use
    if len(empties_in_collection) == 1:
        # Exactly one empty: reuse it
        empty = empties_in_collection[0]
    else:
        # Zero or multiple empties: create a new one
        empty = bpy.data.objects.new(f"{group_name}_pivot", None)
        group_collection.objects.link(empty)
        empty.rotation_mode = 'QUATERNION'
        
        # If there were multiple empties, parent them to the new pivot
        if len(empties_in_collection) > 1:
            for existing_empty in empties_in_collection:
                existing_empty.parent = empty
                existing_empty.matrix_parent_inverse = Matrix.Translation(-target_origin)
    
    # Position the pivot
    empty.location = target_origin
    
    # Parent ALL parent objects to the pivot (meshes, lamps, cameras, etc.)
    for obj in parent_group:
        if obj.type != 'EMPTY':  # Skip any empties in parent_group (to avoid self-parenting issues)
            obj.parent = empty
            obj.matrix_parent_inverse = Matrix.Translation(-target_origin)
    
    return empty


def _apply_transforms_to_pivots(pivots, rots, all_parent_offsets, all_original_rots):
    """Apply group rotations by modifying children's matrix_parent_inverse.
    Pivot empty stays unrotated, but children appear rotated relative to it."""
    
    for i, pivot in enumerate(pivots):
        delta_quat = rots[i]
        # Apply rotation to each child's matrix_parent_inverse
        # This rotates the children relative to the pivot without rotating the pivot itself
        for child in pivot.children:
            rotation_matrix = delta_quat.to_matrix().to_4x4()
            child.matrix_parent_inverse = rotation_matrix @ child.matrix_parent_inverse


def set_origin_and_preserve_children(obj, new_origin_world):
    """Move object origin to new_origin_world while preserving visual placement of mesh and children."""
    old_matrix = obj.matrix_world.copy()
    inv_matrix = old_matrix.to_3x3().inverted()
    world_offset = new_origin_world - old_matrix.translation
    local_offset = inv_matrix @ world_offset
    correction = Matrix.Translation(-local_offset)

    # Apply correction to mesh if it exists
    if hasattr(obj, 'data') and hasattr(obj.data, 'transform'):
        obj.data.transform(correction)

    # Update world location and fix children parenting
    obj.matrix_world.translation = new_origin_world
    for child in obj.children:
        child.matrix_parent_inverse = correction @ child.matrix_parent_inverse



def _prepare_object_transforms(parent_groups, mesh_groups, offsets_mv):
    """
    Extract offset transforms for all groups.
    Returns: (all_parent_offsets, all_original_rots)
    Note: all_original_rots is kept for API compatibility but not used when applying via pivot rotation.
    """
    all_parent_offsets = []
    all_original_rots = []
    
    cdef size_t current_offset_idx = 0
    cdef size_t group_offset_size
    
    for group_idx in range(len(parent_groups)):
        parent_group = parent_groups[group_idx]
        mesh_group = mesh_groups[group_idx]
        group_offset_size = len(mesh_group) * 3  # x, y, z per object
        
        group_offsets_slice = offsets_mv[current_offset_idx:current_offset_idx + group_offset_size]
        parent_offsets = transform_utils.compute_offset_transforms(parent_group, mesh_group, group_offsets_slice)
        all_parent_offsets.append(parent_offsets)
        
        # Set rotation mode for all parent objects
        for obj in parent_group:
            obj.rotation_mode = 'QUATERNION'
        
        current_offset_idx += group_offset_size
    
    return all_parent_offsets, all_original_rots


def _compute_object_locations(parent_groups, rots, all_parent_offsets):
    """Compute new world locations for all objects after rotation."""
    locations = []
    
    cdef Py_ssize_t i, j
    
    for i in range(len(parent_groups)):
        parent_group = parent_groups[i]
        
        # Rotate offsets by group rotation
        rot_matrix = np.array(rots[i].to_matrix())
        offsets = np.asarray(all_parent_offsets[i])
        rotated_offsets = offsets @ rot_matrix.T
        
        # Compute world-space locations
        ref_location = parent_group[0].matrix_world.translation
        for j in range(len(parent_group)):
            loc = (
                ref_location.x + rotated_offsets[j, 0],
                ref_location.y + rotated_offsets[j, 1],
                ref_location.z + rotated_offsets[j, 2]
            )
            locations.append(loc)
    
    return locations


def _apply_object_transforms(parent_groups, all_original_rots, rots, locations, origins):
    """Apply computed rotations and locations to objects in the scene."""
    cdef int obj_idx = 0
    cdef Py_ssize_t i, j
    
    for i, parent_group in enumerate(parent_groups):
        delta_quat = rots[i]
        first_world_loc = parent_group[0].matrix_world.translation.copy()
        target_origin = Vector(origins[i]) + first_world_loc
        
        for obj in parent_group:
            local_quat = all_original_rots[obj_idx]
            location = locations[obj_idx]
            
            # Compose new rotation and preserve existing scale
            new_rotation = (delta_quat @ local_quat).normalized()
            new_location = Vector(location)
            current_scale = obj.matrix_world.to_scale()
            
            # Build world matrix: Translation * Rotation * Scale
            scale_matrix = Matrix.Diagonal(current_scale).to_4x4()
            rotation_matrix = new_rotation.to_matrix().to_4x4()
            translation_matrix = Matrix.Translation(new_location)
            obj.matrix_world = translation_matrix @ rotation_matrix @ scale_matrix
            
            obj_idx += 1
        
        # Update scene cursor for feedback
        bpy.context.scene.cursor.location = target_origin




def standardize_groups(list selected_objects):
    """
    Pro Edition: Classify selected groups via engine.
    
    This function handles group guessing and collection hierarchy:
    1. Aggregate objects into groups by collection boundaries and root parents
    2. Set up pivot empties and ensure proper collection organization
    3. Marshal mesh data into shared memory
    4. Send classify_groups command to engine (performs group-level operations)
    5. Compute new transforms from engine response
    6. Apply transforms to objects
    7. Organize results into surface type collections
    
    Args:
        selected_objects: List of Blender objects selected by the user
    """
    
    # --- Aggregation phase ---
    mesh_groups, parent_groups, full_groups, group_names, total_verts, total_edges, total_objects = \
        selection_utils.aggregate_object_groups(selected_objects)
    core_group_mgr = group_manager.get_group_manager()
    
    # Get engine communicator for the entire function
    engine = get_engine_communicator()
    
    if group_names:
        # --- Set up pivots and ensure proper collections BEFORE engine communication ---
        # We need to compute origins in pre-transform space, so use first object locations as approximation
        first_world_locs = [parent_group[0].matrix_world.translation.copy() for parent_group in parent_groups]
        # Create temporary origins at first object locations (will be updated by engine)
        temp_origins = [tuple(loc) for loc in first_world_locs]
        pivots = _setup_pivots_for_groups_return_empties(parent_groups, group_names, temp_origins, first_world_locs)
        
        # --- Shared memory setup ---
        shm_objects, shm_names, count_memory_views = shm_utils.create_data_arrays(
            total_verts, total_edges, total_objects, mesh_groups)
        
        verts_shm_name, edges_shm_name, rotations_shm_name, scales_shm_name, offsets_shm_name = shm_names
        vert_counts_mv, edge_counts_mv, object_counts_mv, offsets_mv = count_memory_views
        
        # --- Extract transforms and rotation modes ---
        all_parent_offsets, all_original_rots = _prepare_object_transforms(
            parent_groups, mesh_groups, offsets_mv)
        
        # --- Engine communication ---
        command = engine.build_standardize_groups_command(
            verts_shm_name, edges_shm_name, rotations_shm_name, scales_shm_name, offsets_shm_name,
            list(vert_counts_mv), list(edge_counts_mv), list(object_counts_mv), group_names)
        engine.send_command_async(command)
        
        final_response = engine.wait_for_response(1)
        
        # Close shared memory in parent process
        for shm in shm_objects:
            shm.close()
        
        if not bool(final_response.get("ok", True)):
            error_msg = final_response.get("error", "Unknown engine error during classify_groups")
            raise RuntimeError(f"classify_groups failed: {error_msg}")

        groups = final_response["groups"]
        
        # --- Extract and apply transforms ---
        group_names = list(groups.keys())
        rots = [Quaternion(groups[name]["rot"]) for name in group_names]
        origins = [tuple(groups[name]["origin"]) for name in group_names]
        
        # --- Update pivot positions with actual origins from engine ---
        for i, pivot in enumerate(pivots):
            old_pivot_loc = pivot.location.copy()
            new_pivot_loc = Vector(origins[i]) + first_world_locs[i]
            pivot_movement = new_pivot_loc - old_pivot_loc
            
            # Move all children by the opposite amount to keep them visually in place
            for child in pivot.children:
                child.matrix_world.translation -= pivot_movement
            
            # Now update the pivot location
            pivot.location = new_pivot_loc
        
        # --- Apply transforms to PIVOTS (objects follow via parenting) ---
        _apply_transforms_to_pivots(pivots, rots, all_parent_offsets, all_original_rots)
        
        # Build group membership snapshot
        group_membership_snapshot = engine_state.build_group_membership_snapshot(full_groups, group_names)
        engine_state.update_group_membership_snapshot(group_membership_snapshot, replace=False)

    # Always get surface types for ALL stored groups (for organization)
    surface_types_command = engine.build_get_surface_types_command()
    surface_types_response = engine.send_command(surface_types_command)
    
    if not bool(surface_types_response.get("ok", True)):
        error_msg = surface_types_response.get("error", "Unknown engine error during get_surface_types")
        raise RuntimeError(f"get_surface_types failed: {error_msg}")
    
    all_surface_types = surface_types_response.get("groups", {})

    # --- Always organize ALL groups using surface types ---
    if all_surface_types:
        all_group_names = list(all_surface_types.keys())
        surface_types = [all_surface_types[name]["surface_type"] for name in all_group_names]
        
        core_group_mgr.update_managed_group_names(all_group_names)
        core_group_mgr.set_groups_synced(all_group_names)
        
        from pivot.surface_manager import get_surface_manager
        get_surface_manager().organize_groups_into_surfaces(
            core_group_mgr.get_managed_group_names_set(), surface_types)


def standardize_objects(list objects):
    """
    Classify and apply standardization to one or more objects.
    
    This unified function handles both single and multiple objects:
    - Single object (both editions): Direct standardization without group guessing
    - Multiple objects (PRO edition only): Batch processing of multiple objects
    
    Args:
        objects: List of Blender objects to classify (one or more)
    
    Raises:
        RuntimeError: If STANDARD edition tries to classify multiple objects
    """
    if not objects:
        return
    
    # Validation: STANDARD edition only supports single object
    if len(objects) > 1 and not edition_utils.is_pro_edition():
        raise RuntimeError(f"STANDARD edition only supports single object classification, got {len(objects)}")
    
    # Filter to mesh objects only
    mesh_objects = [obj for obj in objects if obj.type == 'MESH']
    if not mesh_objects:
        return
    
    # Build mesh data for all objects
    mesh_groups = [[obj] for obj in mesh_objects]
    
    # Use evaluated depsgraph to account for modifiers that may add verts/edges
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total_verts = 0
    total_edges = 0
    for obj in mesh_objects:
        eval_obj = obj.evaluated_get(depsgraph)
        eval_mesh = eval_obj.data
        total_verts += len(eval_mesh.vertices)
        total_edges += len(eval_mesh.edges)
    
    if total_verts == 0:
        return
    
    # --- Shared memory setup ---
    shm_objects, shm_names, count_memory_views = shm_utils.create_data_arrays(
        total_verts, total_edges, len(mesh_objects), mesh_groups)
    
    verts_shm_name, edges_shm_name, rotations_shm_name, scales_shm_name, offsets_shm_name = shm_names
    vert_counts_mv, edge_counts_mv, object_counts_mv, offsets_mv = count_memory_views
    
    # --- Extract transforms and rotation modes ---
    parent_groups = [[obj] for obj in mesh_objects]
    all_parent_offsets, all_original_rots = _prepare_object_transforms(
        parent_groups, mesh_groups, offsets_mv)
    
    # --- Set up pivots BEFORE engine communication ---
    first_world_locs = [parent_group[0].matrix_world.translation.copy() for parent_group in parent_groups]
    object_names = [obj.name for obj in mesh_objects]
    # Create temporary origins (will be updated by engine)
    temp_origins = [tuple(loc) for loc in first_world_locs]
    pivots = _setup_pivots_for_groups_return_empties(parent_groups, object_names, temp_origins, first_world_locs)
    
    # --- Engine communication: unified array format ---
    # Engine will validate that multiple objects are only used in PRO edition
    engine = get_engine_communicator()
    command = engine.build_standardize_objects_command(
        verts_shm_name, edges_shm_name, rotations_shm_name, scales_shm_name, offsets_shm_name,
        list(vert_counts_mv), list(edge_counts_mv), [obj.name for obj in mesh_objects])
    engine.send_command_async(command)
    
    final_response = engine.wait_for_response(1)
    
    # Close shared memory in parent process
    for shm in shm_objects:
        try:
            shm_name = getattr(shm, "name", "<unknown>")
            shm.close()
        except Exception as e:
            shm_name = getattr(shm, "name", "<unknown>")
            print(f"Warning: Failed to close shared memory segment '{shm_name}': {e}")
            # Continue with other segments even if one fails
    
    if not bool(final_response.get("ok", True)):
        error_msg = final_response.get("error", "Unknown engine error during classify_objects")
        raise RuntimeError(f"classify_objects failed: {error_msg}")

    # --- Extract engine results ---
    # Engine returns results as a dict keyed by object name
    results = final_response.get("results", {})
    rots = [Quaternion(results[obj.name]["rot"]) for obj in mesh_objects if obj.name in results]
    origins = [tuple(results[obj.name]["origin"]) for obj in mesh_objects if obj.name in results]
    
    # --- Update pivot positions with actual origins from engine ---
    for i, pivot in enumerate(pivots):
        old_pivot_loc = pivot.location.copy()
        new_pivot_loc = Vector(origins[i]) + first_world_locs[i]
        pivot_movement = new_pivot_loc - old_pivot_loc
        
        # Move all children by the opposite amount to keep them visually in place
        for child in pivot.children:
            child.matrix_world.translation -= pivot_movement
        
        # Now update the pivot location
        pivot.location = new_pivot_loc
    
    # --- Apply transforms to PIVOTS (objects follow via parenting) ---
    _apply_transforms_to_pivots(pivots, rots, all_parent_offsets, all_original_rots)