# selection_utils.pyx - selection and grouping helpers for Blender objects

import bpy
from . import edition_utils


cpdef object get_root_parent(object obj):
    while obj.parent is not None:
        obj = obj.parent
    return obj


# cpdef list get_all_mesh_descendants(object root):
#     cdef list meshes = []
#     if root.type == 'MESH' and len(root.data.vertices) != 0:
#         meshes.append(root)
#     for child in root.children:
#         meshes.extend(get_all_mesh_descendants(child))
#     return meshes


cpdef tuple get_mesh_and_all_descendants(object root, object depsgraph):
    cdef list meshes = []
    cdef list descendants = [root]
    cdef list stack = [root]
    cdef object current
    cdef object eval_obj
    cdef object eval_mesh
    while stack:
        current = stack.pop()
        if current.type == 'MESH':
            eval_obj = current.evaluated_get(depsgraph)
            eval_mesh = eval_obj.data
            if len(eval_mesh.vertices) != 0:
                meshes.append(current)
        for child in current.children:
            descendants.append(child)
            stack.append(child)
    return meshes, descendants


# cpdef list get_all_descendants(object root):
#     cdef list descendants = [root]
#     for child in root.children:
#         descendants.extend(get_all_descendants(child))
#     return descendants


cpdef list get_all_root_objects(object coll):
    cdef list roots = []
    cdef object obj
    for obj in coll.objects:
        if obj.parent is None:
            roots.append(obj)
    for child in coll.children:
        roots.extend(get_all_root_objects(child))
    return roots


def aggregate_object_groups(list selected_objects, object collection):
    """Group the selection by collection boundaries and root parents."""

    if edition_utils.is_standard_edition() and len(selected_objects) != 1:
        raise ValueError("Standard edition only supports single object selection")

    cdef object depsgraph
    cdef object scene_coll
    cdef dict coll_to_top_map
    cdef object top_coll
    cdef object child_coll
    cdef list stack

    cdef set root_parents
    cdef list mesh_groups
    cdef list parent_groups
    cdef list full_groups
    cdef list group_names
    cdef int total_verts
    cdef int total_edges
    cdef int total_objects

    cdef object root
    cdef list meshes
    cdef list descendants
    cdef list top_roots
    cdef int group_verts
    cdef int group_edges
    cdef bint has_internal

    cdef list selected_top_collections
    cdef set seen_top_collections
    cdef list scene_roots
    cdef set seen_scene_roots

    # Determine scene collection based on edition
    scene_coll = collection
    depsgraph = bpy.context.evaluated_depsgraph_get()

    # Build a lookup that points every nested collection back to its top-level owner.
    coll_to_top_map = {}
    stack = []
    for top_coll in scene_coll.children:
        coll_to_top_map[top_coll] = top_coll
        stack = [(top_coll, top_coll)]
        while stack:
            current_coll, current_top = stack.pop()
            for child_coll in current_coll.children:
                coll_to_top_map[child_coll] = current_top
                stack.append((child_coll, current_top))

    root_parents = set()
    mesh_groups = []
    parent_groups = []
    full_groups = []
    group_names = []
    total_verts = 0
    total_edges = 0
    total_objects = 0

    root = None
    meshes = []
    descendants = []
    top_roots = []
    group_verts = 0
    group_edges = 0
    has_internal = False

    selected_top_collections = []
    seen_top_collections = set()
    scene_roots = []
    seen_scene_roots = set()

    # Deduplicate root parents to avoid processing the same hierarchy multiple times.
    for obj in selected_objects:
        root = get_root_parent(obj)
        root_parents.add(root)

    # Determine which roots belong purely to the scene and which are owned by collections.
    for root in root_parents:
        has_internal = False
        for coll in root.users_collection:
            if coll == scene_coll or coll not in coll_to_top_map:
                continue
            top_coll = coll_to_top_map[coll]
            if top_coll not in seen_top_collections:
                selected_top_collections.append(top_coll)
                seen_top_collections.add(top_coll)
            has_internal = True
        if not has_internal and root not in seen_scene_roots:
            scene_roots.append(root)
            seen_scene_roots.add(root)

    # Add per-root groups for objects that only live at the scene level.
    for root in scene_roots:
        meshes, descendants = get_mesh_and_all_descendants(root, depsgraph)
        group_verts = sum(len(m.evaluated_get(depsgraph).data.vertices) for m in meshes)
        group_edges = sum(len(m.evaluated_get(depsgraph).data.edges) for m in meshes)
        if group_verts > 0:
            mesh_groups.append(meshes)
            parent_groups.append([root])
            full_groups.append(descendants)
            group_names.append(root.name + "_O")
            total_verts += group_verts
            total_edges += group_edges
            total_objects += len(meshes)

    # Add collection-based groups by collapsing all of their root objects.
    for top_coll in selected_top_collections:
        top_roots = get_all_root_objects(top_coll)
        meshes = []
        descendants = []
        for root in top_roots:
            root_meshes, root_descendants = get_mesh_and_all_descendants(root, depsgraph)
            meshes.extend(root_meshes)
            descendants.extend(root_descendants)
        group_verts = sum(len(m.evaluated_get(depsgraph).data.vertices) for m in meshes)
        group_edges = sum(len(m.evaluated_get(depsgraph).data.edges) for m in meshes)
        if group_verts > 0:
            mesh_groups.append(meshes)
            parent_groups.append(top_roots)
            full_groups.append(descendants)
            group_names.append(top_coll.name + "_C")
            total_verts += group_verts
            total_edges += group_edges
            total_objects += len(meshes)

    return mesh_groups, parent_groups, full_groups, group_names, total_verts, total_edges, total_objects
