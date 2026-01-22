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

from pivot_lib.surface_manager import CLASSIFICATION_ROOT_MARKER_PROP

def selected_has_qualifying_objects(selected_objects, objects_collection):
    if not selected_objects or not objects_collection:
        return False

    marker = CLASSIFICATION_ROOT_MARKER_PROP
    sel_set = set(selected_objects)
    
    all_meshes = {o for o in objects_collection.all_objects if o.type == 'MESH'}
    if not all_meshes: return False

    for col in objects_collection.children:
        if col.get(marker): #Skip collections that pivot uses for classification bookkeeping
            continue

        members = set(col.all_objects)

        #Add object groups that include at least one selected object and at least one mesh
        if not members.isdisjoint(sel_set):
            if not members.isdisjoint(all_meshes):
                return True


    for root_obj in objects_collection.objects:
        members = set(root_obj.children_recursive)
        members.add(root_obj)

        if not members.isdisjoint(sel_set):
            if not members.isdisjoint(all_meshes):
                return True

    return False


def get_qualifying_objects_for_selected(selected_objects, objects_collection):
    if not selected_objects or not objects_collection:
        return []

    marker = CLASSIFICATION_ROOT_MARKER_PROP
    sel_set = set(selected_objects)
    
    all_meshes = {o for o in objects_collection.all_objects if o.type == 'MESH'}
    if not all_meshes: return []

    qualifying  = []
    update_qualifying = qualifying.extend

    for col in objects_collection.children:
        if col.get(marker): #Skip collections that pivot uses for classification bookkeeping
            continue

        members = set(col.all_objects)

        #Add object groups that include at least one selected object and at least one mesh
        if not members.isdisjoint(sel_set):
            if not members.isdisjoint(all_meshes):
                update_qualifying(members)


    for root_obj in objects_collection.objects:
        members = set(root_obj.children_recursive)
        members.add(root_obj)

        if not members.isdisjoint(sel_set):
            if not members.isdisjoint(all_meshes):
                update_qualifying(members)

    return qualifying