import bpy
import os
import stat
import sys

from bpy.app.handlers import persistent

from .classes import SceneAttributes
from bpy.props import PointerProperty

from .operators.operators import (
    Splatter_OT_Organize_Classified_Objects,
)
from .operators.classification import (
    Splatter_OT_Classify_Selected,
    Splatter_OT_Classify_Active_Object,
    Splatter_OT_Classify_All_Objects_In_Collection,
)
from .ui import Splatter_PT_Main_Panel
from . import engine
from .property_manager import GROUP_COLLECTION_PROP, get_property_manager

# Globals tracking state for sync detection
_previous_scales = {}
_group_membership_snapshot: dict[str, set[str]] = {}
_is_undoing = False

@persistent
def on_depsgraph_update_fast(scene, depsgraph):
    """
    Checks for geometry updates on selected mesh objects using the depsgraph.updates collection.
    """
    global _group_membership_snapshot, _is_undoing

    pm = get_property_manager()
    if not _group_membership_snapshot:
        _group_membership_snapshot = _snapshot_group_memberships(pm)
        _refresh_object_scales(_group_membership_snapshot)

    if _is_undoing:
        _group_membership_snapshot = _snapshot_group_memberships(pm)
        _refresh_object_scales(_group_membership_snapshot)
        return

    if depsgraph.id_type_updated('OBJECT') or depsgraph.id_type_updated('COLLECTION'):
        current_snapshot = _snapshot_group_memberships(pm)
        all_groups = set(_group_membership_snapshot.keys()) | set(current_snapshot.keys())
        for group_name in all_groups:
            prev_members = _group_membership_snapshot.get(group_name, set())
            curr_members = current_snapshot.get(group_name, set())
            if group_name and prev_members != curr_members:
                pm.mark_group_unsynced(group_name)
                removed_objects = prev_members - curr_members
                for obj_name in removed_objects:
                    _previous_scales.pop(obj_name, None)
                added_objects = curr_members - prev_members
                for obj_name in added_objects:
                    obj = bpy.data.objects.get(obj_name)
                    if obj:
                        _previous_scales[obj_name] = tuple(obj.scale)
        _group_membership_snapshot = current_snapshot

    selected_objects = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    if not selected_objects:
        return

    # Iterate through all updates in the dependency graph.
    for update in depsgraph.updates:
        # Check if the geometry or transform was flagged as updated.
        if update.is_updated_geometry or update.is_updated_transform:
            for obj in selected_objects:
                # Check if the update is for this object's data block (for geometry) or the object itself (for transform).
                if update.id.original == obj.data or update.id.original == obj:
                    group_name = pm.get_group_name(obj)
                    if group_name:
                        current_scale = tuple(obj.scale)
                        prev_scale = _previous_scales.get(obj.name)
                        scale_changed = prev_scale is not None and current_scale != prev_scale
                        group_size = len(_group_membership_snapshot.get(group_name, set()))

                        should_mark_unsynced = (
                            update.is_updated_geometry
                            or scale_changed
                            or (update.is_updated_transform and not scale_changed and group_size > 1)
                        )
                        if should_mark_unsynced:
                            pm.mark_group_unsynced(group_name)

                        _previous_scales[obj.name] = current_scale
                    break  # Found the object for this update, move to next update


@persistent
def _on_undo_pre(_dummy=None):
    global _is_undoing
    _is_undoing = True


@persistent
def _on_undo_post(_dummy=None):
    global _is_undoing, _group_membership_snapshot
    _is_undoing = False
    try:
        pm = get_property_manager()
        _group_membership_snapshot = _snapshot_group_memberships(pm)
        _refresh_object_scales(_group_membership_snapshot)
    except Exception as e:
        print(f"[Splatter] Failed to refresh state after undo: {e}")


bl_info = {
    "name": "Splatter: AI Powered Object Scattering",
    "author": "Nick Wierzbowski",
    "version": (0, 1, 0),
    "blender": (4, 4, 0),  # Minimum Blender version
    "location": "View3D > Sidebar > Splatter",
    "description": "Performs scene segmentation, object classification, and intelligent scattering.",
    "warning": "",
    "doc_url": "",
    "category": "3D View",
}

classesToRegister = (
    SceneAttributes,
    Splatter_PT_Main_Panel,
    Splatter_OT_Classify_Selected,
    Splatter_OT_Classify_Active_Object,
    Splatter_OT_Classify_All_Objects_In_Collection,
    Splatter_OT_Organize_Classified_Objects,
)


def register():
    print(f"Registering {bl_info.get('name')} version {bl_info.get('version')}")
    for cls in classesToRegister:
        bpy.utils.register_class(cls)
    bpy.types.Scene.splatter = PointerProperty(type=SceneAttributes)

    # Ensure engine binary is executable after zip install (zip extraction often drops exec bits)
    try:
        engine_path = os.path.join(os.path.dirname(__file__), 'bin', 'splatter_engine')
        if os.path.exists(engine_path) and os.name != 'nt':
            st = os.stat(engine_path)
            if not (st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)):
                os.chmod(engine_path, st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                print("Fixed executable permissions on splatter engine binary (register)")
    except Exception as e:
        print(f"Note: Could not adjust permissions for engine binary during register: {e}")

    # Start the splatter engine
    engine_started = engine.start_engine()

    if not engine_started:
        print("[Splatter] Failed to start engine")
    else:
        # Print Cython edition for debugging

        try:
            lib_path = os.path.join(os.path.dirname(__file__), 'lib')
            if lib_path not in sys.path:
                sys.path.insert(0, lib_path)
            from .lib import edition_utils
            edition_utils.print_edition()
        except Exception as e:
            print(f"[Splatter] Could not print Cython edition: {e}")
    
    global _group_membership_snapshot, _previous_scales
    _previous_scales.clear()
    try:
        pm = get_property_manager()
        _group_membership_snapshot = _snapshot_group_memberships(pm)
        _refresh_object_scales(_group_membership_snapshot)
    except Exception as e:
        print(f"[Splatter] Could not initialize group membership snapshot: {e}")

    if on_depsgraph_update_fast not in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.append(on_depsgraph_update_fast)
    if _on_undo_pre not in bpy.app.handlers.undo_pre:
        bpy.app.handlers.undo_pre.append(_on_undo_pre)
    if _on_undo_post not in bpy.app.handlers.undo_post:
        bpy.app.handlers.undo_post.append(_on_undo_post)


def unregister():
    print(f"Unregistering {bl_info.get('name')}")
    for cls in reversed(classesToRegister):  # Unregister in reverse order
        bpy.utils.unregister_class(cls)

    del bpy.types.Scene.splatter

    # Sync group classifications to engine before stopping
    try:
        pm = get_property_manager()
        classifications = pm.collect_group_classifications()
        if classifications:
            pm.sync_group_classifications(classifications)
    except Exception as e:
        print(f"Failed to sync classifications before closing: {e}")

    # Stop the splatter engine
    engine.stop_engine()

    # Unregister edit mode hook
    if on_depsgraph_update_fast in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.remove(on_depsgraph_update_fast)
    if _on_undo_pre in bpy.app.handlers.undo_pre:
        bpy.app.handlers.undo_pre.remove(_on_undo_pre)
    if _on_undo_post in bpy.app.handlers.undo_post:
        bpy.app.handlers.undo_post.remove(_on_undo_post)

    global _group_membership_snapshot, _previous_scales, _is_undoing
    _is_undoing = False
    _previous_scales.clear()

def _snapshot_group_memberships(pm) -> dict[str, set[str]]:
    snapshot: dict[str, set[str]] = {}
    for coll in pm.iter_group_collections():
        group_name = coll.get(GROUP_COLLECTION_PROP)
        if not group_name:
            continue
        objects = getattr(coll, "objects", None)
        if objects is None:
            snapshot[group_name] = set()
            continue
        snapshot[group_name] = {obj.name for obj in objects}
    return snapshot


def _refresh_object_scales(snapshot: dict[str, set[str]]) -> None:
    _previous_scales.clear()
    for members in snapshot.values():
        for obj_name in members:
            obj = bpy.data.objects.get(obj_name)
            if obj:
                _previous_scales[obj_name] = tuple(obj.scale)


if __name__ == "__main__":
    register()
