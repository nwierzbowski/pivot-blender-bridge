import bpy
import mathutils
import elbo_sdk_rust as engine
import time

# Import our UUID manager that provides both forward and reverse caching
from pivot_lib import id_manager

MAX_NAME_LEN = 64  # keep in sync with pivot_com_types::MAX_NAME_LEN
temp_mat = mathutils.Matrix()

def sync_timer_callback():
    sync_context = engine.poll_mesh_sync()

    if sync_context is None:
        return 0.01

    start = time.perf_counter()
    for group_index in range(sync_context.size()):
        (verts, edges, transforms, vert_counts, edge_counts, object_names, uuids) = sync_context.buffers(group_index)

        object_count = len(object_names) // MAX_NAME_LEN
        for obj_index in range(object_count):
            # Extract UUID for this object (16 bytes per UUID)
            uuid_start = obj_index * 16  # UUID_SIZE = 16
            uuid_end = uuid_start + 16
            obj_uuid = uuids[uuid_start:uuid_end]

            # Use O(1) lookup for the Blender object instead of string parsing
            # The objects should already be cached via get_or_create_obj_uuid in shm_utils.pyx
            obj = id_manager.get_obj_uuid(bytes(obj_uuid))
            if obj is not None:
                transform_start = obj_index * 16 * 4
                transform_end = transform_start + 16 * 4
                # 1. Cast the flat view into a 2D 4x4 shape
                # This creates a 'view' of the data as 4 rows of 4 floats
                # 1. Keep the view FLAT
                mat_view = transforms[transform_start:transform_end].cast("f")

                # 2. Use a simple generator or zip to chunk it into rows of 4
                # This is much faster than .tolist() because it doesn't create 16 float objects upfront
                it = iter(mat_view)
                mat = mathutils.Matrix(list(zip(it, it, it, it)))

                # 3. Apply
                obj.matrix_world = mat.transposed()
                obj.data.update()
                obj.update_tag()
    end = time.perf_counter()
    print(f"[Pivot] Applied sync for {sync_context.size()} assets in {(end - start) * 1000:.2f} ms")

    start = time.perf_counter()
    # bpy.context.view_layer.update()
    end = time.perf_counter()
    print(f"[Pivot] Depsgraph update took {(end - start) * 1000:.2f} ms")

    return 0