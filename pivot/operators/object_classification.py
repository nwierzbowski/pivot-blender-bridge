import bpy
import time

from ..constants import PRE, FINISHED
from ..lib import standardize
from ..lib import group_manager
from ..classification_utils import get_qualifying_objects_for_selected, selected_has_qualifying_objects


def _standardize_objects(objects, operation_name):
    """Helper function to standardize objects and log timing."""
    # Exit edit mode if active to ensure mesh data is accessible
    if bpy.context.mode == 'EDIT_MESH':
        bpy.ops.object.mode_set(mode='OBJECT')
    
    startTime = time.perf_counter()
    
    standardize.standardize_objects(objects)
    
    endTime = time.perf_counter()
    elapsed = endTime - startTime
    print(f"{operation_name} completed in {(elapsed) * 1000:.2f}ms")


class Pivot_OT_Standardize_Selected_Objects(bpy.types.Operator):
    """
    Pro Edition: Standardize Selected Objects
    
    Standardizes one or more selected objects.
    """
    bl_idname = "object." + PRE.lower() + "standardize_selected_objects"
    bl_label = "Standardize Selected Objects"
    bl_description = "Standardize selected objects"
    bl_options = {"REGISTER", "UNDO"}
    bl_icon = 'OBJECT_DATA'

    @classmethod
    def poll(cls, context):
        sel = getattr(context, "selected_objects", None) or []
        objects_collection = group_manager.get_group_manager().get_objects_collection()
        return selected_has_qualifying_objects(sel, objects_collection)

    def execute(self, context):
        objects_collection = group_manager.get_group_manager().get_objects_collection()
        objects = get_qualifying_objects_for_selected(context.selected_objects, objects_collection)
        _standardize_objects(objects, "Standardize Selected Objects")
        return {FINISHED}


class Pivot_OT_Standardize_Active_Object(bpy.types.Operator):
    """
    Standard Edition: Standardize Active Object
    
    Standardizes the active object only.
    """
    bl_idname = "object." + PRE.lower() + "standardize_active_object"
    bl_label = "Standardize Active Object"
    bl_description = "Standardize the active object"
    bl_options = {"REGISTER", "UNDO"}
    bl_icon = 'OBJECT_DATA'

    @classmethod
    def poll(cls, context):
        obj = context.active_object
        objects_collection = group_manager.get_group_manager().get_objects_collection()
        return obj and selected_has_qualifying_objects([obj], objects_collection)

    def execute(self, context):
        objects_collection = group_manager.get_group_manager().get_objects_collection()
        obj = context.active_object
        if obj and obj in get_qualifying_objects_for_selected([obj], objects_collection):
            _standardize_objects([obj], "Standardize Active Object")
        return {FINISHED}