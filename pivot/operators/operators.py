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

import json
import bpy
import time

from mathutils import Vector

from pivot_lib import engine_state
# import elbo_sdk_rust as engine
from ..constants import (
    CANCELLED,
    FINISHED,
    PRE,
)

from pivot_lib import surface_manager
from pivot_lib import id_manager
from pivot_lib import standardize

import elbo_sdk_rust as engine

class Pivot_OT_Organize_Classified_Objects(bpy.types.Operator):
    bl_idname = "object." + PRE.lower() + "organize_classified_objects"
    bl_label = "Arrange Viewport by Collection"
    bl_description = "Arranges all standardized objects found in the Source Collection into clean rows grouped by class. Note: This operation ignores your current selection"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return id_manager.has_assets()
    def execute(self, context):
        start_total = time.perf_counter()
        try:
            
            # # First, standardize all managed groups
            # asset_uuids = id_manager.get_all_asset_uuids()
            
            # if asset_uuids:
            #     # Collect all objects from managed groups to standardize them
            #     objects_to_standardize = []
            #     for uuid in asset_uuids:
            #         if uuid in bpy.data.collections:
            #             group_coll = bpy.data.collections[uuid]
            #             objects_to_standardize.extend(list(group_coll.objects))
                
            #     if objects_to_standardize:
            #         try:
            #             standardize.standardize_groups(
            #                 objects_to_standardize, 
            #                 "BASE", 
            #                 "AUTO"
            #             )
            #         except Exception as e:
            #             self.report({"WARNING"}, f"Failed to standardize groups: {e}")
            #             print(f"[Pivot] Standardize groups error: {e}")
            

            # classifications = surface_manager.collect_group_classifications()
            # if classifications:
            #     sync_ok = surface_manager.sync_group_classifications(classifications)
            #     if not sync_ok:
            #         self.report({"WARNING"}, "Failed to sync classifications to engine; results may be outdated")

            # Call the engine to organize objects
            start_engine = time.perf_counter()
            engine.organize_objects_command()
            end_engine = time.perf_counter()
                
        except Exception as e:
            end_total = time.perf_counter()
            self.report({"ERROR"}, f"Failed to organize objects: {e}")
            print(f"Organize objects failed - Total time: {(end_total - start_total) * 1000:.2f}ms")
            return {CANCELLED}
        
        end_total = time.perf_counter()
        print(f"Organize objects - Engine call: {(end_engine - start_engine) * 1000:.2f}ms, Total: {(end_total - start_total) * 1000:.2f}ms")
            
        return {FINISHED}


class Pivot_OT_Reset_Classifications(bpy.types.Operator):
    bl_idname = "object." + PRE.lower() + "reset_classifications"
    bl_label = "Reset Classifications"
    bl_description = "Deletes the Pivot Classifications collection and all its related classification collections to reset the classification state"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        try:
            from ..classes import CLASSIFICATION_ROOT_MARKER_PROP, CLASSIFICATION_MARKER_PROP
            
            # Find and delete all classification collections
            collections_to_delete = []
            
            # First pass: find all collections marked as classification collections
            for coll in bpy.data.collections:
                if coll.get(CLASSIFICATION_ROOT_MARKER_PROP, False) or coll.get(CLASSIFICATION_MARKER_PROP, False):
                    collections_to_delete.append(coll)
            
            # Delete found collections
            deleted_count = 0
            for coll in collections_to_delete:
                try:
                    # Unlink from scene if it's a root collection
                    scene = context.scene
                    if scene.collection.children.find(coll.name) != -1:
                        scene.collection.children.unlink(coll)
                    
                    # Remove the collection entirely
                    bpy.data.collections.remove(coll)
                    deleted_count += 1
                except RuntimeError as e:
                    print(f"[Pivot] Failed to delete collection '{coll.name}': {e}")
                    self.report({"WARNING"}, f"Failed to delete collection: {coll.name}")
            
            if deleted_count > 0:
                self.report({"INFO"}, f"Reset classifications: deleted {deleted_count} collection(s)")
                engine_state.set_performing_classification(True)
            else:
                self.report({"INFO"}, "No classification collections found to reset")
            
            return {FINISHED}
            
        except Exception as e:
            self.report({"ERROR"}, f"Failed to reset classifications: {e}")
            print(f"[Pivot] Reset classifications error: {e}")
            return {CANCELLED}


class Pivot_OT_Upgrade_To_Pro(bpy.types.Operator):
    bl_idname = PRE.lower() + ".upgrade_to_pro"
    bl_label = "Upgrade to Pro"
    bl_description = "Visit our website!"

    def execute(self, context):
        bpy.ops.wm.url_open(url="https://elbo.studio")
        return {FINISHED}
