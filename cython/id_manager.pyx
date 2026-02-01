
import elbo_sdk_rust as engine

# Session cache: Python Object Reference -> bytes(16)
# This prevents calling obj.get() every frame during Live Link
_obj_uuid_cache = {}
_asset_uuid_cache = {}

def get_or_create_obj_uuid(obj):
    # 1. Check our lightning-fast session cache first
    if obj in _obj_uuid_cache:
        return _obj_uuid_cache[obj]

    # 2. Check Blender's persistent data
    # Custom properties are stored in the .blend file
    uuid_bytes = obj.get("pivot_id")

    if uuid_bytes is None:
        # 3. Create if doesn't exist
        # Call the Rust generator we made above
        uuid_bytes = bytes(engine.generate_uuid_bytes())
        # Save to Blender property (Persists in .blend)
        obj["pivot_id"] = uuid_bytes
    else:
        # Blender returns a 'IDPropertyArray' or 'bytes'
        # Ensure it's a standard Python bytes object for the cache
        uuid_bytes = bytes(uuid_bytes)

    # 4. Update session cache and return
    _obj_uuid_cache[obj] = uuid_bytes
    return uuid_bytes

def get_or_create_asset_uuid(list cols):
    cdef list uuids = []
    for col in cols:
        # 1. Check our lightning-fast session cache first
        if col in _asset_uuid_cache:
            uuids.append(_asset_uuid_cache[col])
            continue

        # 2. Check Blender's persistent data
        uuid_bytes = col.get("pivot_asset_id")

        if uuid_bytes is None:
            # 3. Create if doesn't exist
            uuid_bytes = bytes(engine.generate_uuid_bytes())
            # Save to Blender property (Persists in .blend)
            col["pivot_asset_id"] = uuid_bytes
        else:
            uuid_bytes = bytes(uuid_bytes)

        # 4. Update session cache and return
        _asset_uuid_cache[col] = uuid_bytes
        uuids.append(uuid_bytes)
    return uuids

