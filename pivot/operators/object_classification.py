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

import bpy
import time

from ..constants import PRE, FINISHED, LICENSE_PRO
from pivot_lib import standardize
from ..classification_utils import get_qualifying_objects_for_selected, selected_has_qualifying_objects
from pivot_lib.engine_state import get_engine_license_status
from pivot_lib import timer_manager

# Operator descriptions
DESC_SET_ORIGIN_SELECTED = "Applies the configured 'Origin Method' to each selected object, respecting the chosen 'Surface Context'. Use this to fix only the origins without affecting rotation"
DESC_ALIGN_FACING_SELECTED = "Applies the 'Align Facing' rotation to each selected object, respecting the chosen 'Surface Context' to determine the correct 'forward' direction"

class Pivot_OT_Set_Origin_Selected_Objects(bpy.types.Operator):
    """
    Sets origin for one or more selected objects.
    """
    bl_idname = "object." + PRE.lower() + "set_origin_selected_objects"
    bl_label = "Standardize Object Origin"
    bl_description = DESC_SET_ORIGIN_SELECTED
    bl_options = {"REGISTER", "UNDO"}
    bl_icon = 'OBJECT_DATA'

    @classmethod
    def poll(cls, context):
        # timer_manager.timers.start("set_origin_selected_objects.any_qualifying")
        sel = getattr(context, "selected_objects", None) or []
        scene_collection = getattr(context.scene, "collection", None)
        if not scene_collection:
            return False
        # print("set_origin_selected_objects.any_qualifying: ", timer_manager.timers.stop("set_origin_selected_objects.any_qualifying"), "ms")
        # timer_manager.timers.reset("set_origin_selected_objects.any_qualifying")
        return selected_has_qualifying_objects(sel)

    def execute(self, context):
        timer_manager.timers.start("set_origin_selected_objects")

        scene_collection = getattr(context.scene, "collection", None)
        if not scene_collection:
            return {FINISHED}
        timer_manager.timers.start("set_origin_selected_objects.get_qualifying")
        objects = get_qualifying_objects_for_selected(context.selected_objects)
        # Exit edit mode if active to ensure mesh data is accessible
        if bpy.context.mode == 'EDIT_MESH':
            bpy.ops.object.mode_set(mode='OBJECT')
        print("set_origin_selected_objects.get_qualifying: ", timer_manager.timers.stop("set_origin_selected_objects.get_qualifying"), "ms")
        timer_manager.timers.reset("set_origin_selected_objects.get_qualifying")
        
        license_type = get_engine_license_status()
        origin_method = context.scene.pivot.origin_method
        surface_type = context.scene.pivot.surface_type
        if license_type != LICENSE_PRO and len(objects) > 1:
            for obj in objects:
                standardize.standardize_object_origins([obj], origin_method=origin_method, surface_context=surface_type)
        else:
            standardize.standardize_object_origins(objects, origin_method=origin_method, surface_context=surface_type)
       
        print("set_origin_selected_objects.underhead: ", timer_manager.timers.stop("set_origin_selected_objects.underhead"), "ms")
        timer_manager.timers.reset("set_origin_selected_objects.underhead")

        
        print(f"set_origin_selected_objects {timer_manager.timers.stop('set_origin_selected_objects'):.2f}ms")
        timer_manager.timers.reset("set_origin_selected_objects")
        return {FINISHED}


class Pivot_OT_Align_Facing_Selected_Objects(bpy.types.Operator):
    """
    Aligns facing for one or more selected objects.
    """
    bl_idname = "object." + PRE.lower() + "align_facing_selected_objects"
    bl_label = "Standardize Object Rotation"
    bl_description = DESC_ALIGN_FACING_SELECTED
    bl_options = {"REGISTER", "UNDO"}
    bl_icon = 'OBJECT_DATA'

    @classmethod
    def poll(cls, context):
        sel = getattr(context, "selected_objects", None) or []
        scene_collection = getattr(context.scene, "collection", None)
        if not scene_collection:
            return False
        return selected_has_qualifying_objects(sel)

    def execute(self, context):
        scene_collection = getattr(context.scene, "collection", None)
        if not scene_collection:
            return {FINISHED}
        objects = get_qualifying_objects_for_selected(context.selected_objects)
        # Exit edit mode if active to ensure mesh data is accessible
        if bpy.context.mode == 'EDIT_MESH':
            bpy.ops.object.mode_set(mode='OBJECT')
        
        startTime = time.perf_counter()
        
        license_type = get_engine_license_status()
        if license_type != LICENSE_PRO and len(objects) > 1:
            for obj in objects:
                standardize.standardize_object_rotations([obj])
        else:
            standardize.standardize_object_rotations(objects)
        
        endTime = time.perf_counter()
        elapsed = endTime - startTime
        print(f"Align Facing Selected Objects completed in {(elapsed) * 1000:.2f}ms")
        return {FINISHED}


