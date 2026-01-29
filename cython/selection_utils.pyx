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

# selection_utils.pyx - selection and grouping helpers for Blender objects

# cython: language_level=3
import bpy
from . import edition_utils
from pivot_lib import group_manager

# Constants (must match pivot/surface_manager.py)
CLASSIFICATION_MARKER_PROP = "pivot_is_classification_collection"
CLASSIFICATION_ROOT_MARKER_PROP = "pivot_is_classification_root"


cdef str MESH_TYPE = "MESH"

def aggregate_object_groups(list selected_objects):
    """Group the selection by collection boundaries and root parents."""

    if edition_utils.is_standard_edition() and len(selected_objects) != 1:
        raise ValueError("Standard edition only supports single object selection")

    cdef object group_mgr = group_manager.get_group_manager()
    cdef object scene_coll = group_mgr.get_objects_collection()
    
    if not scene_coll.objects and not scene_coll.children:
        return [], []

    # Get Depsgraph (Unavoidable overhead on first run)
    cdef object depsgraph = bpy.context.evaluated_depsgraph_get()
    cdef str marker = CLASSIFICATION_MARKER_PROP

    # --- 1. Selection Setup ---
    cdef set sel_set = set(selected_objects)
    
    # Filter selection to meshes only. 
    # This is small (User selection size), so it's fast.
    cdef set sel_set_meshes = {o for o in sel_set if o.type == MESH_TYPE}
    
    if not sel_set_meshes:
        return [], []

    # REMOVED: Global `all_meshes` generation. 
    # We no longer scan the whole scene at startup.

    cdef list group_names = []
    cdef list mesh_groups = []
    
    cdef object col
    cdef object root_obj
    cdef object new_col
    cdef object obj
    cdef object eval_obj
    cdef object eval_mesh
    
    cdef set col_objects_set
    cdef list eval_members
    cdef str new_col_name

    cdef list mesh_members_list = []
    
    # --- 2. Pass 1: Existing Collections ---
    for col in scene_coll.children:
        if col.get(marker):
            continue

        col_objects_set = set(col.all_objects)
        
        # Optimization: Fail-Fast
        # If the collection doesn't touch our selection, skip it entirely.
        if col_objects_set.isdisjoint(sel_set_meshes):
            continue

        # If we are here, this collection is relevant.
        # NOW we filter for meshes, only on this specific subset.
        eval_members = []
        for obj in col_objects_set:
            if obj.type == MESH_TYPE:
                # We also check if it's in the selection OR in the scene_coll scope
                # (Assuming col.all_objects implies it is in scope, we just need type check)
                try:
                    eval_obj = obj.evaluated_get(depsgraph)
                    eval_mesh = eval_obj.data
                    eval_members.append((eval_obj, eval_mesh, eval_mesh.vertices, eval_mesh.edges))
                except (RuntimeError, AttributeError):
                    continue

        if eval_members:
            mesh_groups.append(eval_members)
            group_names.append(col.name)

    # --- 3. Pass 2: Root Objects ---
    # Iterate over tuple copy to handle list mutation safely
    for root_obj in tuple(scene_coll.objects):
        
        # Build hierarchy set
        if root_obj.type == MESH_TYPE:
            col_objects_set = set(root_obj.children_recursive)
            col_objects_set.add(root_obj)
        else:
            col_objects_set = set(root_obj.children_recursive)

        # Optimization: Fail-Fast
        if col_objects_set.isdisjoint(sel_set_meshes):
            continue

        # Process valid hierarchy
        eval_members = []
        mesh_members_list = [] # Temporary list for relinking

        for obj in col_objects_set:
            if obj.type == MESH_TYPE:
                try:
                    eval_obj = obj.evaluated_get(depsgraph)
                    eval_mesh = eval_obj.data
                    eval_members.append((eval_obj, eval_mesh, eval_mesh.vertices, eval_mesh.edges))
                    mesh_members_list.append(obj)
                except (RuntimeError, AttributeError):
                    continue
        
        if eval_members:
            mesh_groups.append(eval_members)

            # Create new collection
            new_col_name = f"{root_obj.name}"
            new_col = bpy.data.collections.new(new_col_name)
            scene_coll.children.link(new_col)
            group_names.append(new_col.name)

            # Relink objects
            for obj in mesh_members_list:
                try:
                    if obj.name in scene_coll.objects:
                        scene_coll.objects.unlink(obj)
                    if obj.name not in new_col.objects:
                        new_col.objects.link(obj)
                except RuntimeError:
                    pass

    return mesh_groups, group_names