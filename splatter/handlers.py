# Depsgraph Update Handlers
# ---------------------------
# Handles Blender depsgraph updates for detecting scene changes and maintaining sync state.

import bpy
from bpy.app.handlers import persistent

from . import engine_state
from .lib import group_manager

# Cache of each object's last-known scale to detect transform-only edits quickly.
_previous_scales: dict[str, tuple[float, float, float]] = {}


@persistent
def on_depsgraph_update(scene, depsgraph):
    """Orchestrate all depsgraph update handlers in guaranteed order."""
    if engine_state._is_performing_classification:
        engine_state._is_performing_classification = False
    else:
        detect_collection_hierarchy_changes(scene, depsgraph)
        unsync_mesh_changes(scene, depsgraph)
    enforce_colors(scene, depsgraph)


def detect_collection_hierarchy_changes(scene, depsgraph):
    """Detect changes in collection hierarchy and mark affected groups as out-of-sync with the engine."""
    group_mgr = group_manager.get_group_manager()
    
    current_snapshot = group_mgr.get_group_membership_snapshot()
    expected_snapshot = engine_state.get_group_membership_snapshot()
    for group_name, expected_members in expected_snapshot.items():
        current_members = current_snapshot.get(group_name, set())
        if expected_members != current_members:
            group_mgr.set_group_unsynced(group_name)


def enforce_colors(scene, depsgraph):
    """Enforce correct color tags for group collections based on sync state."""
    group_mgr = group_manager.get_group_manager()
    group_mgr.update_orphaned_groups()
    group_mgr.update_colors()


def unsync_mesh_changes(scene, depsgraph):
    """Detect mesh and transform changes on selected objects and mark groups as unsynced."""
    group_mgr = group_manager.get_group_manager()
    expected_snapshot = engine_state.get_group_membership_snapshot()
    current_snapshot = group_mgr.get_group_membership_snapshot()

    selected_objects = [obj for obj in bpy.context.selected_objects if obj.type == 'MESH']
    if selected_objects:
        for update in depsgraph.updates:
            if not (update.is_updated_geometry or update.is_updated_transform):
                continue

            for obj in selected_objects:
                if update.id.original not in (obj, obj.data):
                    continue

                group_name = group_mgr.get_group_name(obj)
                if not group_name:
                    break

                expected_members = expected_snapshot.get(group_name)
                current_members = current_snapshot.get(group_name, set())
                member_count = len(expected_members) if expected_members is not None else len(current_members)

                current_scale = tuple(obj.scale)
                prev_scale = _previous_scales.get(obj.name)
                scale_changed = prev_scale is not None and current_scale != prev_scale

                should_mark_unsynced = (
                    expected_members is None
                    or (update.is_updated_geometry)
                    or scale_changed
                    or (update.is_updated_transform and not scale_changed and member_count > 1)
                )

                if should_mark_unsynced:
                    group_mgr.set_group_unsynced(group_name)

def clear_previous_scales():
    """Clear the scale cache used for detecting transform changes."""
    global _previous_scales
    _previous_scales.clear()


def on_group_name_changed(collection, group_mgr):
    """Callback for when a managed group's name changes.
    
    Args:
        collection: The collection whose name changed
        group_mgr: The GroupManager instance
    """
    name_tracker = group_mgr.get_name_tracker()
    sync_state = group_mgr.get_sync_state_dict()
    orphaned_groups = group_mgr.get_orphaned_groups_set()
    
    old_name = name_tracker.get(collection)
    new_name = collection.name

    if old_name and old_name != new_name:
        print(f"[Splatter] Group '{old_name}' renamed to '{new_name}'")
        
        # Update sync state to reflect the new name
        if old_name in sync_state:
            synced = sync_state.pop(old_name)
            sync_state[new_name] = synced
        
        # Update orphaned groups set if needed
        if old_name in orphaned_groups:
            orphaned_groups.discard(old_name)
            orphaned_groups.add(new_name)
    
    # Update the tracker with the new name
    name_tracker[collection] = new_name