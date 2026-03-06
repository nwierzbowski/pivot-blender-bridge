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

import elbo_sdk_rust as engine
import bpy

# Reverse cache: bytes(16) -> [Python Object Reference, state flag]
# This enables O(1) lookup during mesh sync with per-object state tracking
# Using mutable lists to allow in-place flag updates without tuple recreation
# Separate caches for objects and collections
obj_uuid_cache = {}  # uuid -> [obj]
col_uuid_cache = {}  # uuid -> [collection, bool_flag]
membership_cache = {} # asset uuid -> [obj uuids...]
parent_cache = {} # object uuid -> asset uuid

PIVOT_ASSET_ID = "pivot_asset_id"
PIVOT_OBJECT_ID = "pivot_id"

def get_objects_collection() -> Optional[Any]:
        """Get the objects collection from the scene's pivot properties."""
        objects_collection = bpy.context.scene.pivot.objects_collection
        return objects_collection if objects_collection else bpy.context.scene.collection

def drop_assets(list uuids):
    for uuid in uuids:
        if uuid in col_uuid_cache and uuid in membership_cache:
            col_uuid_cache[uuid][0].color_tag = 'NONE'

            obj_uuids = membership_cache[uuid]
            _drop_objects(obj_uuids)
            del col_uuid_cache[uuid]
            del membership_cache[uuid]
        else:
            print("Tried to drop asset: ", uuid, ", but did not exist in both asset caches")

def _drop_objects(list uuids):
    for uuid in uuids:
        if uuid in obj_uuid_cache and uuid in parent_cache:
            del obj_uuid_cache[uuid]
            del parent_cache[uuid]
        else:
            print("Tried to drop object: ", uuid, ", but did not exist in both object caches")


def set_asset_membership(bytes asset_uuid, unsigned char[:] obj_uuids):
    cdef Py_ssize_t num_uuids = len(obj_uuids) // 16

    cdef Py_ssize_t i

    # Since we are reseting the asset membership cache we must also remove that asset from the its previous objects' parent caches
    # Should be cheap as usually there is only one member anyways
    if asset_uuid in membership_cache:
        prev_members = membership_cache[asset_uuid]
        for mem in prev_members:
            parent_cache[mem].remove(asset_uuid)

    # Reset that asset's membership cache
    membership_cache[asset_uuid] = []

    # Add the uuids to the new membership cache and the asset to their parent caches
    for i in range(num_uuids):
        uuid_bytes = bytes(obj_uuids[i*16:(i+1)*16])
        membership_cache[asset_uuid].append(uuid_bytes)
        parent_cache.setdefault(uuid_bytes, []).append(asset_uuid)

def get_asset_members(bytes uuid):
    return membership_cache[uuid]

def get_obj_asset(bytes uuid):
    return parent_cache[uuid]

def get_all_asset_uuids():
    return col_uuid_cache.keys()

def get_all_obj_uuids():
    return obj_uuid_cache.keys()

def reset_state():
    for uuid in col_uuid_cache:
        entry =  col_uuid_cache[uuid]
        entry[0].color_tag = 'NONE'
    col_uuid_cache.clear()
    obj_uuid_cache.clear()
    membership_cache.clear()
    parent_cache.clear()

def has_assets():
    return bool(col_uuid_cache)

def has_asset(bytes uuid):
    return uuid in col_uuid_cache

def _get_or_create_uuid(obj, prop_name, cache):
    """Helper function to get or create UUID for object or collection."""

    if prop_name not in obj:
        uuid_bytes = bytes(engine.generate_uuid_bytes())
        obj[prop_name] = uuid_bytes
    else:
        uuid_bytes = obj[prop_name]
        uuid_bytes = bytes(uuid_bytes)
    return uuid_bytes

def get_or_create_obj_uuids(list objs):
    cdef list uuids = []
    for obj in objs:
        uuid_bytes = _get_or_create_uuid(obj, PIVOT_OBJECT_ID, obj_uuid_cache)
        obj_uuid_cache[uuid_bytes] = [obj]
        uuids.append(uuid_bytes)
    return uuids

def get_or_create_asset_uuid(list cols):
    cdef list uuids = []
    for col in cols:
        uuid_bytes = _get_or_create_uuid(col, PIVOT_ASSET_ID, col_uuid_cache)
        col_uuid_cache[uuid_bytes] = [col, False]
        uuids.append(uuid_bytes)
    return uuids

def get_obj_by_uuid(list uuids):
    """Pure function to get UUID for object without creating it if it doesn't exist."""
    cdef list objs = []
    for uuid in uuids:
        entry = obj_uuid_cache[uuid]
        objs.append(entry[0])
    return objs  # Return just the object, not the flag

def get_asset_by_uuid(list uuids):
    """Pure function to get collections by UUIDs without creating them."""
    cdef list cols = []
    for uuid in uuids:
        entry = col_uuid_cache[uuid]
        cols.append(entry[0])  # Return just the collection
    return cols


# Functions to set the sync for UUIDS
def set_sync(bytes uuid, bint value):
    """Update the boolean flag for a collection's UUID."""
    entry = col_uuid_cache.get(uuid)
    
    if entry is not None:
        if entry[1] != value:
            col = entry[0]
            
            if value:
                col.color_tag = 'COLOR_04'  # Green
            else:
                col.color_tag = 'COLOR_03'  # Yellow
                
            entry[1] = value
            
    else:
        print(f"[Pivot Error] Sync called on missing UUID: {uuid}")

def set_sync_batch(unsigned char[:] asset_uuids, bint value):
    cdef Py_ssize_t num_uuids = len(asset_uuids) // 16
    cdef Py_ssize_t i

    for i in range(num_uuids):
        uuid_bytes = bytes(asset_uuids[i*16:(i+1)*16])
        set_sync(uuid_bytes, value)


def get_asset_uuids_from_view(unsigned char[:] asset_uuids):
    """Get collections from a flat byte memoryview (16 bytes per UUID).
    
    Zero-copy optimized version that processes all UUIDs in a single Cython loop.
    Returns list of Blender collections directly.
    
    Args:
        asset_uuids: Flat memoryview of bytes, length must be multiple of 16
        
    Returns:
        List of collection objects (one per UUID found in cache)
    """
    cdef Py_ssize_t num_uuids = len(asset_uuids) // 16
    cdef list cols = []
    cdef Py_ssize_t i
    
    for i in range(num_uuids):
        uuid_bytes = bytes(asset_uuids[i*16:(i+1)*16])
        cols.append(col_uuid_cache[uuid_bytes][0])
    
    return cols

