
import elbo_sdk_rust as engine

# Reverse cache: bytes(16) -> [Python Object Reference, state flag]
# This enables O(1) lookup during mesh sync with per-object state tracking
# Using mutable lists to allow in-place flag updates without tuple recreation
# Separate caches for objects and collections
_obj_uuid_cache = {}  # uuid -> [obj, bool_flag]
_col_uuid_cache = {}  # uuid -> [collection, bool_flag]

def _get_or_create_uuid(obj, prop_name, cache):
    """Helper function to get or create UUID for object or collection."""
    # 1. Check Blender's persistent data
    
    
    if prop_name not in obj:
        # 2. Create if doesn't exist
        # Call the Rust generator we made above
        uuid_bytes = bytes(engine.generate_uuid_bytes())
        # Save to Blender property (Persists in .blend)
        obj[prop_name] = uuid_bytes
    else:
        uuid_bytes = obj[prop_name]
        # Blender returns a 'IDPropertyArray' or 'bytes'
        # Ensure it's a standard Python bytes object for the cache
        uuid_bytes = bytes(uuid_bytes)
    
    # 3. Update reverse cache for O(1) lookup during mesh sync
    # Store as list: [object, state_flag], default flag is True
    cache[uuid_bytes] = [obj, False]

    return uuid_bytes

def get_or_create_obj_uuids(list objs):
    cdef list uuids = []
    for obj in objs:
        uuid_bytes = _get_or_create_uuid(obj, "pivot_id", _obj_uuid_cache)
        uuids.append(uuid_bytes)
    return uuids

def get_or_create_asset_uuid(list cols):
    cdef list uuids = []
    for col in cols:
        uuid_bytes = _get_or_create_uuid(col, "pivot_asset_id", _col_uuid_cache)
        uuids.append(uuid_bytes)
    return uuids

def get_obj_uuid(uuid):
    """Pure function to get UUID for object without creating it if it doesn't exist."""
    entry = _obj_uuid_cache[uuid]
    return entry[0]  # Return just the object, not the flag

def get_asset_uuid(list uuids):
    """Pure function to get collections by UUIDs without creating them."""
    cdef list cols = []
    for uuid in uuids:
        entry = _col_uuid_cache[uuid]
        cols.append(entry[0])  # Return just the collection
    return cols


# Functions to set the sync for UUIDS
def set_sync(bytes uuid, bint value):
    """Update the boolean flag for a collection's UUID."""
    if uuid in _col_uuid_cache:
        entry =  _col_uuid_cache[uuid]
       
        col = entry[0]
        state = entry[1]
        if state != value:
            if value:
                col.color_tag = 'COLOR_04'
            else:
                col.color_tag = 'COLOR_03'
            state = value

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
        cols.append(_col_uuid_cache[uuid_bytes][0])
    
    return cols

