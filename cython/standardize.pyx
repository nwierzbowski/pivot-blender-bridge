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

import bpy
import json

from . import selection_utils, shm_utils, edition_utils
from .timer_manager import timers
from . import id_manager, surface_manager


# Collection metadata keys
GROUP_COLLECTION_PROP = "pivot_group_name"
CLASSIFICATION_ROOT_COLLECTION_NAME = "Pivot"
CLASSIFICATION_COLLECTION_PROP = "pivot_surface_type"

def _build_group_surface_contexts(asset_uuids, surface_context):
    """Build per-group surface context strings, honoring AUTO overrides with stored classifications."""

    if not asset_uuids:
        return []

    contexts = []
    auto_context = surface_context == "AUTO"
    if auto_context:
        map_to_use = surface_manager.collect_group_classifications()

        if not map_to_use:
            return [3] * len(asset_uuids)

        for uuid in asset_uuids:
            if uuid in map_to_use:
                surface_type_int = map_to_use[uuid]
                if surface_type_int in (1, 2, 3):
                    contexts.append(surface_type_int)
                else:
                    contexts.append(0)

        return contexts
    else:
        return [int(surface_context)] * len(asset_uuids)

def standardize_groups(list selected_objects, str origin_method, str surface_context):
    """Pro Edition: Classify selected groups via engine."""

    timers.start("standardize_groups.aggregate_object_groups")
    mesh_groups, group_names, collections = selection_utils.aggregate_object_groups(selected_objects)
    print("standardize_groups.aggregate_object_groups: ", timers.stop("standardize_groups.aggregate_object_groups"), "ms")
    timers.reset("standardize_groups.aggregate_object_groups")

    if collections:
        asset_uuids = id_manager.get_or_create_asset_uuid(collections)

        surface_contexts = _build_group_surface_contexts(asset_uuids, surface_context)

        context = shm_utils.create_data_arrays(mesh_groups, group_names, asset_uuids, surface_contexts)

        timers.start("engine.compute")
        try:
            print("Starting finalize")
            final_json = context.finalize(True)
            print("Ending finalize")
        except Exception as e:
            print ("BIG ERROR")
            print(e)
        final_response = json.loads('{"ok": true }')
        
        print("engine.compute: ", timers.stop("engine.compute"), "ms")
        timers.reset("engine.compute")

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
    
    timers.start("get_standardize_results.depsgraph")

    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh_groups = []
    group_names = []
    targets = []
    for obj in objects:
        eval_obj = obj.evaluated_get(depsgraph)
        eval_mesh = eval_obj.data
        eval_verts = eval_mesh.vertices
        eval_edges = eval_mesh.edges
        if len(eval_verts) == 0:
            continue
        mesh_groups.append([(eval_obj, eval_mesh, eval_verts, eval_edges, eval_mesh.loops, eval_mesh.polygons)])
        group_names.append(obj.name)
        targets.append(obj)
    
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
    context = shm_utils.create_data_arrays(
        mesh_groups,
        group_names,
        id_manager.get_or_create_obj_uuids(targets),
        surface_contexts
    )
    print("create_data_arrays.total: ", timers.stop("create_data_arrays.total"), "ms")
    timers.reset("create_data_arrays.total")


    timers.start("engine.compute")
    try:
        print("Starting finalize")
        final_json = context.finalize(False)
        print("Ending finalize")
    except Exception as e:
        print ("BIG ERROR")
        print(e)
    final_response = json.loads('{"ok": true }')
    
    print("engine.compute: ", timers.stop("engine.compute"), "ms")
    timers.reset("engine.compute")



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