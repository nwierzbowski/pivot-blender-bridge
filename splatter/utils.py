import os
import bpy
import time

from .constants import ASSETS_FILENAME
from .lib import classify_object
from .engine_state import set_engine_has_groups_cached


def link_node_group(self, node_group_name):
    addon_dir = os.path.dirname(__file__)
    asset_filepath = os.path.join(addon_dir, ASSETS_FILENAME)

    if not os.path.exists(asset_filepath):
        self.report({"ERROR"}, f"Asset file not found! Expected at: {asset_filepath}")
        return {"CANCELLED"}

    if node_group_name not in bpy.data.node_groups:
        try:
            with bpy.data.libraries.load(asset_filepath, link=True) as (
                data_from,
                data_to,
            ):
                if node_group_name in data_from.node_groups:
                    data_to.node_groups = [node_group_name]
                else:
                    self.report(
                        {"ERROR"},
                        f"Node group '{node_group_name}' not in {ASSETS_FILENAME}",
                    )
                    return {"CANCELLED"}
        except Exception as e:
            self.report({"ERROR"}, f"Failed to link node group: {e}")
            return {"CANCELLED"}

    ng = bpy.data.node_groups[node_group_name]
    if not ng:
        self.report({"ERROR"}, "Failed to access linked node group.")
        return {"CANCELLED"}

    return ng


def get_all_mesh_objects_in_collection(coll):
    meshes = []
    for obj in coll.objects:
        if obj.type == 'MESH':
            meshes.append(obj)
    for child in coll.children:
        meshes.extend(get_all_mesh_objects_in_collection(child))
    return meshes


def get_qualifying_objects_for_selected(selected_objects, objects_collection):
    qualifying = []
    scene_root = objects_collection
    for obj in selected_objects:
        if obj.type == 'MESH' and scene_root in obj.users_collection:
            qualifying.append(obj)

    # Check for selected objects in scene_root that have mesh descendants
    def has_mesh_descendants(obj):
        for child in obj.children:
            if child.type == 'MESH' or has_mesh_descendants(child):
                return True
        return False

    for obj in selected_objects:
        if scene_root in obj.users_collection and has_mesh_descendants(obj):
            qualifying.append(obj)

    # Build a map of every nested collection to its top-level (direct child of scene_root)
    coll_to_top = {}

    def traverse(current_coll, current_top):
        for child in current_coll.children:
            coll_to_top[child] = current_top
            traverse(child, current_top)

    for top in scene_root.children:
        coll_to_top[top] = top
        traverse(top, top)

    # Cache for whether a top-level collection's subtree contains any mesh
    top_has_mesh_cache = {}

    def coll_has_mesh(coll):
        # Fast boolean check: any mesh in this collection or its children
        for o in coll.objects:
            if o.type == 'MESH':
                return True
        for child in coll.children:
            if coll_has_mesh(child):
                return True
        return False

    for obj in selected_objects:
        # Consider all collections the object belongs to
        for coll in getattr(obj, 'users_collection', []) or []:
            if coll is scene_root:
                continue
            top = coll_to_top.get(coll)
            if not top:
                continue
            if top not in top_has_mesh_cache:
                top_has_mesh_cache[top] = coll_has_mesh(top)
            if top_has_mesh_cache[top]:
                qualifying.append(obj)
                break  # once added, no need to check more collections

    return list(set(qualifying))  # remove duplicates


def perform_classification(objects, objects_collection):
    startCPP = time.perf_counter()
    
    classify_object.classify_and_apply_objects(objects, objects_collection)
    endCPP = time.perf_counter()
    elapsedCPP = endCPP - startCPP
    print(f"Total time elapsed: {(elapsedCPP) * 1000:.2f}ms")
    
    # Mark that we now have classified objects/groups
    set_engine_has_groups_cached(True)
