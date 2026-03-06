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

# Blender Event Handlers
# -----------------------
# Handles Blender lifecycle events including:
# - File load/save events (load_pre, load_post)
# - Depsgraph updates (on_depsgraph_update)

import bpy
from bpy.app.handlers import persistent
import os
import sys
import stat

from .mesh_sync import sync_timer_callback
from pivot_lib import engine_state
import elbo_sdk_rust as engine
from pivot_lib import surface_manager
from pivot_lib import id_manager
import time

# Cache of each object's last-known world matrix (by UUID) to detect transform changes.
_previous_world_matrices: dict[str, list[list[float]]] = {}  # keyed by obj_uuid


@persistent
def on_depsgraph_update(scene, depsgraph):
    """Orchestrate all depsgraph update handlers in guaranteed order."""
    start_time = time.time()
    if engine_state.is_performing_classification():
        engine_state.set_performing_classification(False)
    else:
        detect_collection_hierarchy_changes(scene, depsgraph)
        unsync_mesh_changes(scene, depsgraph)
    end_time = time.time()
    print(f"on_depsgraph_update took {1000 * (end_time - start_time):.4f} milliseconds")


def detect_collection_hierarchy_changes(scene, depsgraph):
    """Detect changes in collection hierarchy and mark affected groups as out-of-sync with the engine."""

    # Filter for collection changes
    hierarchy_changed = False
    for update in depsgraph.updates:
        if type(update.id) is bpy.types.Collection:
            hierarchy_changed = True
            break

    if not hierarchy_changed:
        return

    scene_col = id_manager.get_objects_collection()

    expected_asset_uuids = set(id_manager.get_all_asset_uuids())

    cur_asset_uuids = set(u.get(id_manager.PIVOT_ASSET_ID) for u in scene_col.children if u.get(id_manager.PIVOT_ASSET_ID))

    MESH_TYPE = "MESH"

    dropped_assets = list(expected_asset_uuids.difference(cur_asset_uuids))
    if dropped_assets:
        id_manager.drop_assets(dropped_assets)
        engine.drop_groups_command(dropped_assets)
        print(f"[Pivot] Dropped {dropped_assets} from engine")

    for asset_uuid in id_manager.get_all_asset_uuids():
        uuids = id_manager.get_asset_members(asset_uuid)
        objs = set(id_manager.get_obj_by_uuid(uuids))
        cur_objs = {o for o in id_manager.get_asset_by_uuid([asset_uuid])[0].all_objects if o.type == MESH_TYPE}

        synced = objs != cur_objs
        if not synced:
            id_manager.set_sync(asset_uuid, synced)

def unsync_mesh_changes(scene, depsgraph):
    """Detect mesh and transform changes on selected objects and mark groups as unsynced."""
    global _previous_world_matrices
    
    if not bpy.context.selected_objects:
        return  # No selected objects, nothing to do
    
    selected_uuids = {o.get(id_manager.PIVOT_OBJECT_ID) for o in bpy.context.selected_objects if o.get(id_manager.PIVOT_OBJECT_ID)}
    selected_objects = selected_uuids.intersection(set(id_manager.get_all_obj_uuids()))
    
    if not selected_objects:
        return  # No selected objects in managed collections

    # Main processing loop
    for update in depsgraph.updates:
        if not (update.is_updated_geometry or update.is_updated_transform):
            continue

        obj = update.id.original
        obj_uuid = obj.get(id_manager.PIVOT_OBJECT_ID)

        if not obj_uuid in selected_uuids:
            continue

        asset_uuids = id_manager.get_obj_asset(obj_uuid)
        for uuid in asset_uuids:
            # Convert world matrix to tuple for comparison
            current_world_matrix = [list(col) for col in zip(*obj.matrix_world)]
            prev_world_matrix = _previous_world_matrices.get(obj_uuid)
            transform_changed = prev_world_matrix is not None and current_world_matrix != prev_world_matrix

            should_mark_unsynced = update.is_updated_geometry or transform_changed

            if should_mark_unsynced:
                id_manager.set_sync(uuid, not should_mark_unsynced)

        # Update world matrix cache for next handler invocation
        _previous_world_matrices[obj_uuid] = current_world_matrix

def clear_previous_scales():
    """Clear the world matrix cache used for detecting transform changes."""
    global _previous_world_matrices
    _previous_world_matrices.clear()


# File Load Handlers
# ------------------
# Manage engine lifecycle and state synchronization around file load/save events.

@persistent
def on_load_pre(scene):
    """Executed before a new file is loaded.
    
    Shuts down the engine and syncs any pending classification state before file load.
    """
    try:
        # Sync any pending group classifications to the engine before shutting down
        surface_mgr = surface_manager.get_surface_manager()
        classifications = surface_mgr.collect_group_classifications()
        if classifications:
            surface_mgr.sync_group_classifications(classifications)
    except Exception as e:
        print(f"[Pivot] Failed to sync classifications before load: {e}")

    print("[Pivot] Unregistering sync timer callback")
    if bpy.app.timers.is_registered(sync_timer_callback):
        bpy.app.timers.unregister(sync_timer_callback)
    # Stop the pivot engine
    engine.stop_engine()

@persistent
def on_load_post(scene):
    """Executed after a new file has finished loading.
    
    Starts the engine up again for the new scene and initializes local tracked state.
    """
    # Reset GroupManager state for the new scene
    # group_manager.get_group_manager().reset_state()
    id_manager.reset_state()
    
    # Initialize engine state for the new scene
    engine_state.update_group_membership_snapshot({}, replace=True)
    clear_previous_scales()

    engine.start_engine()
    print("[Pivot] Registering sync timer callback")
    if not bpy.app.timers.is_registered(sync_timer_callback):
        bpy.app.timers.register(sync_timer_callback)
    
    
    