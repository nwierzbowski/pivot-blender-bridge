import bpy

bl_info = {
    "name": "My Awesome 3D DL Addon",
    "author": "Your Name",
    "version": (0, 1, 0),
    "blender": (3, 0, 0),  # Minimum Blender version
    "location": "View3D > Sidebar > My DL Addon Tab",
    "description": "Performs scene segmentation, object classification, and intelligent scattering.",
    "warning": "",
    "doc_url": "",
    "category": "3D View",
}


# Placeholder for your classes
# class MYADDON_OT_InstallDependencies(bpy.types.Operator): ...
# class MYADDON_PT_MainPanel(bpy.types.Panel): ...


def register():
    print("Registering My Awesome 3D DL Addon")
    # bpy.utils.register_class(MYADDON_OT_InstallDependencies)
    # bpy.utils.register_class(MYADDON_PT_MainPanel)
    pass  # You'll add class registrations here later


def unregister():
    print("Unregistering My Awesome 3D DL Addon")
    # bpy.utils.unregister_class(MYADDON_OT_InstallDependencies)
    # bpy.utils.unregister_class(MYADDON_PT_MainPanel)
    pass  # You'll add class unregistrations here later


if __name__ == "__main__":
    register()
