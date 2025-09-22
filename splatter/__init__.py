import bpy
import os
import stat
import subprocess
import atexit

from .classes import ObjectAttributes
from bpy.props import PointerProperty
from bpy.app.handlers import persistent

from .operators import (
    Splatter_OT_Align_To_Axes,
    Splatter_OT_Classify_Base,
    Splatter_OT_Classify_Object,
    Splatter_OT_Selection_To_Seating,
    Splatter_OT_Selection_To_Surfaces,
    Splatter_OT_Classify_Faces,
    Splatter_OT_Generate_Base,
    Splatter_OT_Segment_Scene,
    Splatter_OT_Select_Surfaces,
    Splatter_OT_Select_Seating,
)
from .ui import Splatter_PT_Main_Panel
from . import engine
from . import engine_state


@persistent
def sync_engine_after_undo(_dummy=None):
    """Sync engine properties after undo/redo via PropertyManager (deduped per group/attr).

    Marked persistent so it survives file loads; uses bpy.context.scene instead of a
    handler argument to be compatible with Blender's undo/redo handler signature.
    """
    print("Syncing engine after undo/redo...")
    from .property_manager import get_property_manager

    synced_count, touched_groups = get_property_manager().sync_scene_after_undo(bpy.context.scene)
    if synced_count > 0:
        print(f"Undo/Redo sync: {synced_count} properties synchronized across {touched_groups} groups")




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
    ObjectAttributes,
    Splatter_OT_Segment_Scene,
    Splatter_OT_Generate_Base,
    Splatter_OT_Classify_Base,
    Splatter_PT_Main_Panel,
    Splatter_OT_Classify_Faces,
    Splatter_OT_Select_Surfaces,
    Splatter_OT_Selection_To_Surfaces,
    Splatter_OT_Select_Seating,
    Splatter_OT_Selection_To_Seating,
    Splatter_OT_Classify_Object,
    Splatter_OT_Align_To_Axes,
)


def register():
    print(f"Registering {bl_info.get('name')} version {bl_info.get('version')}")
    for cls in classesToRegister:
        bpy.utils.register_class(cls)
    bpy.types.Object.classification = PointerProperty(type=ObjectAttributes)

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
    engine.start_engine()
    
    # Register undo handler to sync engine after undo operations
    if sync_engine_after_undo not in bpy.app.handlers.undo_post:
        bpy.app.handlers.undo_post.append(sync_engine_after_undo)
    if sync_engine_after_undo not in bpy.app.handlers.redo_post:
        bpy.app.handlers.redo_post.append(sync_engine_after_undo)

    # Example: Add addon preferences (if you create an AddonPreferences class)
    # bpy.utils.register_class(MyAddonPreferences)

    # Example: Add custom properties to Blender's scene or objects
    # bpy.types.Scene.my_addon_property = bpy.props.StringProperty(...)

    # TODO: Add logic here or call a utility function to:
    # 1. Check if Python virtual environments for DL models exist.
    # 2. If not, inform the user or provide a button (in the UI registered above)
    #    to trigger their creation and dependency installation.
    #    This setup should ideally only run once or when needed, not every time
    #    Blender starts and the addon is enabled. You might use a flag in addon prefs.


def unregister():
    print(f"Unregistering {bl_info.get('name')}")
    for cls in reversed(classesToRegister):  # Unregister in reverse order
        bpy.utils.unregister_class(cls)

    del bpy.types.Object.classification

    # Stop the splatter engine
    engine.stop_engine()
    
    # Unregister undo handlers
    if sync_engine_after_undo in bpy.app.handlers.undo_post:
        bpy.app.handlers.undo_post.remove(sync_engine_after_undo)
    if sync_engine_after_undo in bpy.app.handlers.redo_post:
        bpy.app.handlers.redo_post.remove(sync_engine_after_undo)

    # Example: Remove addon preferences
    # bpy.utils.unregister_class(MyAddonPreferences)

    # Example: Delete custom properties
    # del bpy.types.Scene.my_addon_property


if __name__ == "__main__":
    register()
