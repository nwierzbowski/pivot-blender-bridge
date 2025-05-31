import bpy


class MYADDON_PT_MainPanel(bpy.types.Panel):
    bl_label = "My DL Addon"
    bl_idname = "MYADDON_PT_MainPanel"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "My DL Addon"  # Tab name in the N-Panel

    def draw(self, context):
        layout = self.layout
        layout.label(text="Deep Learning Operations:")
        layout.operator("myaddon.segment_scene", text="Segment Current Scene")
        # Add more operators here later
        layout.separator()
        layout.label(text="Setup:")
        # layout.operator("myaddon.install_dependencies", text="Install Dependencies")
