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

# standardize.pyx - Classifies and applies transformations to Blender objects.
#
# This module handles:
# - Communicating with the C++ engine to compute object classifications
# - Computing and applying new world-space transforms based on engine output
# - Managing collection hierarchy for surface type classification (Pro edition)

from mathutils import Quaternion, Vector, Matrix

import bpy
import json

from . import selection_utils, shm_utils, edition_utils, group_manager
from . import engine_state
import elbo_sdk_rust as engine
from .surface_manager import get_surface_manager
from multiprocessing.shared_memory import SharedMemory
from .timer_manager import timers

# Collection metadata keys
GROUP_COLLECTION_PROP = "pivot_group_name"
CLASSIFICATION_ROOT_COLLECTION_NAME = "Pivot"
CLASSIFICATION_COLLECTION_PROP = "pivot_surface_type"

def _apply_transforms_to_pivots(pivots, origins, rots, cogs, bint origin_method_is_base):
    """Apply position and rotation transforms to pivots using the chosen origin method."""

    for i, pivot in enumerate(pivots):
        if pivot is None:
            continue

        is_base = group_manager.get_group_manager().was_object_last_transformed_using_base(pivot)
        if not is_base:
            pivot.matrix_world.translation -= Vector(cogs[i])
            
        origin_vector = Vector(origins[i]) if origin_method_is_base else Vector(cogs[i])
        pivot_world_rot = pivot.matrix_world.to_quaternion()
        world_rot = pivot_world_rot @ rots[i]
        rotation_matrix = world_rot.to_matrix().to_4x4()

        world_cog = pivot.matrix_world @ Vector(cogs[i])
        world_origin = pivot.matrix_world @ origin_vector
        target_origin = world_cog + rotation_matrix @ (world_origin - world_cog)

        local_cog = Vector(cogs[i])
        local_origin = origin_vector
        local_rotation_matrix = rots[i].to_matrix().to_4x4()

        pre_rotate = Matrix.Translation(local_rotation_matrix @ (local_cog - local_origin)) @ local_rotation_matrix
        post_translate = Matrix.Translation(-local_cog)
        for child in pivot.children:
            child.matrix_local = pre_rotate @ post_translate @ child.matrix_local

        pivot.matrix_world.translation = target_origin

def _build_group_surface_contexts(group_names, surface_context, classification_map=None):
    """Build per-group surface context strings, honoring AUTO overrides with stored classifications."""

    if not group_names:
        return []

    contexts = []
    auto_context = surface_context == "AUTO"
    map_to_use = classification_map
    if auto_context and map_to_use is None:
        map_to_use = get_surface_manager().collect_group_classifications()
    if map_to_use is None:
        map_to_use = {}

    for name in group_names:
        if auto_context and name in map_to_use:
            surface_type_int = map_to_use[name]
            if surface_type_int in (1, 2, 3):
                contexts.append(surface_type_int)
            else:
                contexts.append(0)
        else:
            # surface_context is already in the correct format (AUTO, 0, 1, 2)
            if surface_context in ("1", "2", "3"):
                contexts.append(int(surface_context))
            else:
                contexts.append(0)  # default to AUTO

    return contexts

def _standardize_synced_groups(synced_group_names, surface_contexts):
    """Reclassify cached groups without sending mesh data."""

    if not synced_group_names:
        return {}


    final_response = json.loads(engine.standardize_synced_groups_command(synced_group_names, surface_contexts))
    return final_response.get("groups", {})

def standardize_groups(list selected_objects, str origin_method, str surface_context):
    """Pro Edition: Classify selected groups via engine."""

    timers.start("standardize_groups.aggregate_object_groups")
    mesh_groups, group_names = selection_utils.aggregate_object_groups(selected_objects)
    print("standardize_groups.aggregate_object_groups: ", timers.stop("standardize_groups.aggregate_object_groups"), "ms")
    timers.reset("standardize_groups.aggregate_object_groups")

    # core_group_mgr = group_manager.get_group_manager()
    # origin_method_is_base = origin_method == "BASE"

    # new_group_results = {}
    # transformed_group_names = []

    #Retain old classifications for user correction support
    # classification_map = None
    # if surface_context == "AUTO" and (group_names or synced_group_names):
    #     classification_map = get_surface_manager().collect_group_classifications()

    if (surface_context):
        if surface_context == "AUTO":
            context = 0
        elif surface_context == "1":
            context = 1
        elif surface_context == "2":
            context = 2
        elif surface_context == "3":
            context = 3
        else:
            context = 0

    if group_names:
        # surface_contexts = _build_group_surface_contexts(group_names, surface_context, classification_map)

        shm_utils.create_data_arrays(mesh_groups, group_names, [context] * len(group_names))

        # new_group_results = final_response["groups"]
        # transformed_group_names = list(new_group_results.keys())

        # group_membership_snapshot = engine_state.build_group_membership_snapshot(full_groups, transformed_group_names)
        # engine_state.update_group_membership_snapshot(group_membership_snapshot, replace=False)

    # synced_surface_contexts = _build_group_surface_contexts(synced_group_names, surface_context, classification_map)
    # synced_group_results = _standardize_synced_groups(synced_group_names, synced_surface_contexts)

    # all_group_results = {**new_group_results, **synced_group_results}
    # all_transformed_group_names = list(all_group_results.keys())

    # if all_transformed_group_names:
    #     all_rots = [Quaternion(all_group_results[name]["rot"]) for name in all_transformed_group_names]
    #     all_origins = [tuple(all_group_results[name]["origin"]) for name in all_transformed_group_names]
    #     all_cogs = [tuple(all_group_results[name]["cog"]) for name in all_transformed_group_names]

    #     pivot_lookup = {group_names[i]: pivots[i] for i in range(len(group_names))}
    #     pivot_lookup.update({synced_group_names[i]: synced_pivots[i] for i in range(len(synced_group_names))})
    #     all_pivots = []
    #     for name in all_transformed_group_names:
    #         pivot = pivot_lookup.get(name)
    #         if pivot is None:
    #             print(f"Warning: Pivot not found for group '{name}'")
    #         all_pivots.append(pivot)

    #     _apply_transforms_to_pivots(all_pivots, all_origins, all_rots, all_cogs, origin_method_is_base)
    #     core_group_mgr.set_groups_last_origin_method_base(all_transformed_group_names, origin_method_is_base)

    # surface_types_response = json.loads(engine.get_surface_types_command())
    
    # if not bool(surface_types_response.get("ok", True)):
    #     error_msg = surface_types_response.get("error", "Unknown engine error during get_surface_types")
    #     raise RuntimeError(f"get_surface_types failed: {error_msg}")
    
    # all_surface_types = surface_types_response.get("groups", {})
    # # print(all_surface_types)

    # # --- Always organize ALL groups using surface types ---
    # if all_surface_types:
    #     # Use the response order directly instead of converting to list and back
    #     # This preserves the engine's ordering and prevents group/surface type misalignment
    #     all_group_names = list(all_surface_types.keys())
    #     surface_types = [all_surface_types[name]["surface_type"] for name in all_group_names]
        
    #     # Verify we have matching counts to prevent misalignment
    #     if len(all_group_names) != len(surface_types):
    #         raise RuntimeError(f"Mismatch between group names ({len(all_group_names)}) and surface types ({len(surface_types)})")
        
    #     core_group_mgr.update_managed_group_names(all_group_names)
    #     core_group_mgr.set_groups_synced(all_group_names)
        
    #     # Pass as parallel lists with verified alignment to avoid swapping
    #     get_surface_manager().organize_groups_into_surfaces(all_group_names, surface_types)

def _get_standardize_results(list objects, str surface_context="AUTO"):
    """
    Helper function to get standardization results from the engine.
        
    Returns mesh_objects, rots, origins, cogs
    """
    if not objects:
        return [], [], [], []
    
    # Validation: STANDARD edition only supports single object
    if len(objects) > 1 and not edition_utils.is_pro_edition():
        raise RuntimeError(f"STANDARD edition only supports single object classification, got {len(objects)}")
    
    # # Filter to mesh objects only
    # mesh_objects = [obj for obj in objects if obj.type == 'MESH']
    # if not mesh_objects:
    #     return [], [], [], []

    # Build mesh data for all objects (each object is its own group).
    # Use evaluated objects/meshes and provide the same tuple shape
    # used by the pro/group code: (eval_obj, eval_mesh, verts, edges)
    timers.start("get_standardize_results.depsgraph")

    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh_groups = []
    group_names = []
    for obj in objects:
        eval_obj = obj.evaluated_get(depsgraph)
        eval_mesh = eval_obj.data
        eval_verts = eval_mesh.vertices
        eval_edges = eval_mesh.edges
        if len(eval_verts) == 0:
            continue
        mesh_groups.append([(eval_obj, eval_mesh, eval_verts, eval_edges)])
        group_names.append(obj.name)
    
    print("get_standardize_results.depsgraph: ", timers.stop("get_standardize_results.depsgraph"), "ms")
    timers.reset("get_standardize_results.depsgraph")

    if not mesh_groups:
        return [], [], [], []
    # Map surface_context to engine-expected string
    if surface_context in ("0", "1", "2"):
        engine_surface_context = int(surface_context)
    else:
        engine_surface_context = 0
    surface_contexts = [engine_surface_context] * len(mesh_groups)

    timers.start("create_data_arrays.total")
    final_response = shm_utils.create_data_arrays(
        mesh_groups,
        group_names,
        surface_contexts,
    )
    print("create_data_arrays.total: ", timers.stop("create_data_arrays.total"), "ms")
    timers.reset("create_data_arrays.total")
    timers.start("set_origin_selected_objects.underhead")
    
    if not bool(final_response.get("ok", True)):
        error_msg = final_response.get("error", "Unknown engine error during standardize_groups")
        raise RuntimeError(f"standardize_groups failed: {error_msg}")



def standardize_object_origins(list objects, str origin_method, str surface_context="AUTO"):
    """Standardize object origins."""
    _get_standardize_results(objects, surface_context)
    

def standardize_object_rotations(list objects):
    """Standardize object rotations."""
    _get_standardize_results(objects)