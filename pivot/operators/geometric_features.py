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

from pivot_lib import id_manager
from ..constants import (
    CANCELLED,
    FINISHED,
    PRE,
)
from ..classification_utils import get_qualifying_groups_for_selected, selected_has_qualifying_groups

import elbo_sdk_rust as engine


class Pivot_OT_Extract_Geometric_Features(bpy.types.Operator):
    bl_idname = PRE.lower() + ".extract_geometric_features"
    bl_label = "Extract Geometric Features"
    bl_description = "Extract geometric features from selected assets for testing purposes. Selects entire asset groups based on selection (collection-based or parent-child hierarchies)"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        sel = getattr(context, "selected_objects", None) or []
        if not sel:
            return False
        
        # Check if any selected objects have UUIDs already stored in id_manager
        all_obj_uuids = id_manager.get_all_obj_uuids()
        return bool(all_obj_uuids)

    def execute(self, context):
        start_total = time.perf_counter()
        try:
            # Exit edit mode if active
            if bpy.context.mode == 'EDIT_MESH':
                bpy.ops.object.mode_set(mode='OBJECT')

            selected_objects = set(context.selected_objects)
            
            # Get all object UUIDs already stored in id_manager
            obj_uuid_to_obj = {uuid: entry[0] for uuid, entry in id_manager.obj_uuid_cache.items()}
            
            # Filter to only objects that are in the selection
            selected_obj_uuids = [
                uuid for uuid, obj in obj_uuid_to_obj.items() 
                if obj in selected_objects
            ]
            
            if not selected_obj_uuids:
                self.report({"WARNING"}, "No selected objects have UUIDs stored in id_manager")
                return {CANCELLED}

            # Get unique asset UUIDs from the selected objects
            asset_uuids_set = set()
            for obj_uuid in selected_obj_uuids:
                # Get parent asset UUIDs using id_manager function (returns list of asset UUIDs)
                asset_uuid_list = id_manager.get_obj_asset(obj_uuid)
                for asset_uuid in asset_uuid_list:
                    asset_uuids_set.add(asset_uuid)
                    # print(asset_uuid)

            if not asset_uuids_set:
                self.report({"WARNING"}, "Could not find asset UUIDs for selected objects")
                return {CANCELLED}

            # Get collections using id_manager function instead of direct cache access
            asset_uuids_list = list(asset_uuids_set)
            # collections = id_manager.get_asset_by_uuid(asset_uuids_list)

            # # Collect UUIDs for the command
            # uuid_list = []

            # for uuid_bytes in asset_uuids_set:
            #     # Convert bytes to tuple of integers for PyO3 to extract as [u8; 16]
            #     uuid_tuple = tuple(uuid_bytes)
            #     uuid_list.append(uuid_tuple)

            # Call the engine to extract geometric features
            start_engine = time.perf_counter()
            engine.extract_geometric_features_command(list(asset_uuids_set))
            end_engine = time.perf_counter()

            self.report({"INFO"}, f"Extracted geometric features for {len(asset_uuids_set)} asset(s)")
            print(f"[Pivot] Extracted geometric features - Engine call: {(end_engine - start_engine) * 1000:.2f}ms")

        except Exception as e:
            end_total = time.perf_counter()
            self.report({"ERROR"}, f"Failed to extract geometric features: {e}")
            print(f"[Pivot] Extract geometric features error: {e}")
            import traceback
            traceback.print_exc()
            return {CANCELLED}

        end_total = time.perf_counter()
        print(f"Extract geometric features - Total time: {(end_total - start_total) * 1000:.2f}ms")
        
        return {FINISHED}