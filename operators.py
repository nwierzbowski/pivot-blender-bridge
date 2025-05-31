import bpy

from .constants import PRE


class Splatter_OT_Segment_Scene(bpy.types.Operator):
    bl_idname = PRE.lower() + ".segment_scene"
    bl_label = "Segment Scene"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        print("Segment Scene Operator Called (Not Implemented Yet)")
        self.report({"INFO"}, "Scene Segmentation (Not Implemented Yet)")
        return {"FINISHED"}
