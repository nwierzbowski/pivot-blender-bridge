
import elbo_sdk_rust as engine

# Reverse cache: bytes(16) -> Python Object Reference
# This enables O(1) lookup during mesh sync
# Separate caches for objects and collections
_obj_uuid_cache = {}
_col_uuid_cache = {}

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
    cache[uuid_bytes] = obj
    
    return uuid_bytes

def get_or_create_obj_uuid(obj):
    return _get_or_create_uuid(obj, "pivot_id", _obj_uuid_cache)

def get_or_create_asset_uuid(list cols):
    cdef list uuids = []
    for col in cols:
        uuid_bytes = _get_or_create_uuid(col, "pivot_asset_id", _col_uuid_cache)
        uuids.append(uuid_bytes)
    return uuids

def get_obj_uuid(uuid):
    """Pure function to get UUID for object without creating it if it doesn't exist."""
    return _obj_uuid_cache[uuid]

def get_asset_uuid(list uuids):
    """Pure function to get UUIDs for collections without creating them if they don't exist."""
    cdef list cols = []
    for uuid in uuids:
        cols.append(uuid)
    return cols

