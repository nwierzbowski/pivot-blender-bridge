import bpy
import mathutils
import elbo_sdk_rust as engine

MAX_NAME_LEN = 64  # keep in sync with pivot_com_types::MAX_NAME_LEN

def sync_timer_callback():

    sync_context = engine.poll_mesh_sync()

    if sync_context is None:
        return 0.01
    
    for group_index in range(sync_context.size()):
        (verts, edges, transforms, vert_counts, edge_counts, object_names, uuids) = sync_context.buffers(group_index)

        object_count = len(object_names) // MAX_NAME_LEN
        for obj_index in range(object_count):
            name_start = obj_index * MAX_NAME_LEN
            name_end = name_start + MAX_NAME_LEN
            name_bytes = bytes(object_names[name_start:name_end]).split(b"\x00", 1)[0]
            obj_name = name_bytes.decode("utf-8", errors="ignore")
            if not obj_name:
                continue
                
            obj = bpy.data.objects.get(obj_name)
            if obj is not None:
                transform_start = obj_index * 16 * 4
                transform_end = transform_start + 16 * 4
                mat_view = transforms[transform_start:transform_end].cast("f", shape=(4, 4))
                mat = mathutils.Matrix(mat_view.tolist())
                obj.matrix_world = mat
                obj.data.update()

    return 0