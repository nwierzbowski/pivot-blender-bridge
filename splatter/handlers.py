# Depsgraph Update Handlers
# ---------------------------
# Handles Blender depsgraph updates for detecting scene changes and maintaining sync state.

import bpy
from bpy.app.handlers import persistent

from . import engine_state
from .lib import group_manager
import time

# Cache of each object's last-known scale to detect transform-only edits quickly.
_previous_scales: dict[str, tuple[float, float, float]] = {}


@persistent
def on_depsgraph_update(scene, depsgraph):
    """Orchestrate all depsgraph update handlers in guaranteed order."""
    start_time = time.time()
    if engine_state._is_performing_classification:
        engine_state._is_performing_classification = False
    else:
        detect_collection_hierarchy_changes(scene, depsgraph)
        unsync_mesh_changes(scene, depsgraph)
    enforce_colors(scene, depsgraph)
    end_time = time.time()
    print(f"on_depsgraph_update took {1000 * (end_time - start_time):.4f} milliseconds")


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
    global _previous_scales
    
    start_time = time.perf_counter()
    
    group_mgr = group_manager.get_group_manager()
    snapshots_time = time.perf_counter()
    expected_snapshot = engine_state.get_group_membership_snapshot()
    current_snapshot = group_mgr.get_group_membership_snapshot()
    snapshots_time = time.perf_counter() - snapshots_time

    # Get all selected mesh objects
    selected_mesh_time = time.perf_counter()
    all_selected_mesh = [obj for obj in bpy.context.selected_objects if obj.type == 'MESH']
    selected_mesh_time = time.perf_counter() - selected_mesh_time
    
    # Filter to only objects in managed collections that are in sync and not orphaned
    # Build a set of all objects in managed collections (faster than checking each object)
    orphaned_time = time.perf_counter()
    orphaned_groups = set(group_mgr.get_orphaned_groups())  # Convert to set for O(1) lookups
    managed_group_names = group_mgr.get_sync_state_keys()  # Already returns a set
    orphaned_time = time.perf_counter() - orphaned_time
    
    filtering_time = time.perf_counter()
    selected_objects = []
    obj_to_group = {}
    
    # Iterate through managed collections and find selected objects in them
    for group_name in managed_group_names:
        if group_name in orphaned_groups or group_name not in expected_snapshot:
            continue
        
        # Get the collection
        coll = bpy.data.collections.get(group_name)
        if not coll:
            continue
        
        # Check objects in this collection
        for obj in coll.objects:
            if obj in all_selected_mesh:
                selected_objects.append(obj)
                obj_to_group[obj] = group_name
    
    filtering_time = time.perf_counter() - filtering_time
    
    if not selected_objects:
        total_time = time.perf_counter() - start_time
        print(f"unsync_mesh_changes: early return - {1000 * total_time:.4f}ms total")
        return

    # obj_to_group is already built above, no need for separate precompute step
    precompute_time = 0.0
    
    # Build reverse lookup for O(1) matching: update.id.original -> obj
    lookup_time = time.perf_counter()
    id_to_obj = {}
    for obj in selected_objects:
        id_to_obj[id(obj)] = obj
        id_to_obj[id(obj.data)] = obj
    lookup_time = time.perf_counter() - lookup_time

    # Main processing loop
    loop_time = time.perf_counter()
    for update in depsgraph.updates:
        if not (update.is_updated_geometry or update.is_updated_transform):
            continue

        # O(1) lookup instead of O(m) loop
        obj = id_to_obj.get(id(update.id.original))
        if obj is None:
            continue

        group_name = obj_to_group.get(obj)
        # Group name is guaranteed to be valid since we filtered selected_objects

        expected_members = expected_snapshot.get(group_name)
        current_members = current_snapshot.get(group_name, set())
        member_count = len(expected_members) if expected_members is not None else len(current_members)

        current_scale = tuple(obj.scale)
        prev_scale = _previous_scales.get(obj.name)
        scale_changed = prev_scale is not None and current_scale != prev_scale

        should_mark_unsynced = (
            expected_members is None
            or update.is_updated_geometry
            or scale_changed
            or (update.is_updated_transform and not scale_changed and member_count > 1)
        )

        if should_mark_unsynced:
            group_mgr.set_group_unsynced(group_name)

        # Update scale cache for next handler invocation
        _previous_scales[obj.name] = current_scale
    
    loop_time = time.perf_counter() - loop_time
    total_time = time.perf_counter() - start_time
    
    print(f"unsync_mesh_changes timing: {1000 * total_time:.4f}ms total")
    print(f"  snapshots: {1000 * snapshots_time:.4f}ms ({100 * snapshots_time/total_time:.1f}%)")
    print(f"  selected_mesh: {1000 * selected_mesh_time:.4f}ms ({100 * selected_mesh_time/total_time:.1f}%)")
    print(f"  orphaned: {1000 * orphaned_time:.4f}ms ({100 * orphaned_time/total_time:.1f}%)")
    print(f"  filtering: {1000 * filtering_time:.4f}ms ({100 * filtering_time/total_time:.1f}%)")
    print(f"  lookup: {1000 * lookup_time:.4f}ms ({100 * lookup_time/total_time:.1f}%)")
    print(f"  loop: {1000 * loop_time:.4f}ms ({100 * loop_time/total_time:.1f}%)")
    print(f"  objects processed: {len(selected_objects)}, updates processed: {len(depsgraph.updates)}")

def clear_previous_scales():
    """Clear the scale cache used for detecting transform changes."""
    global _previous_scales
    _previous_scales.clear()