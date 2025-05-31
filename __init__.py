import bpy
from .operators import Splatter_OT_Segment_Scene
from .ui import Splatter_PT_Main_Panel

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

classesToRegister = (Splatter_OT_Segment_Scene, Splatter_PT_Main_Panel)


def register():
    print(f"Registering {bl_info.get('name')} version {bl_info.get('version')}")
    for cls in classesToRegister:
        bpy.utils.register_class(cls)

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

    # Example: Remove addon preferences
    # bpy.utils.unregister_class(MyAddonPreferences)

    # Example: Delete custom properties
    # del bpy.types.Scene.my_addon_property


if __name__ == "__main__":
    register()
