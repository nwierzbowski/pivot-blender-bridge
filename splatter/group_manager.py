"""Group management for Blender collections.

Responsibilities:
- Manage group collections and their metadata
- Handle group membership operations
- Provide group-related queries and utilities
"""

import bpy
from typing import Any, Dict, Iterator, Optional, Set

from .collection_manager import get_collection_manager

class GroupManager:
    """Manages group collections and their metadata."""

    def __init__(self) -> None:
        self._collection_manager = get_collection_manager()
        self._managed_collection_names: Set[str] = set()

    def get_objects_collection(self) -> Optional[Any]:
        """Get the objects collection from the scene's splatter properties."""
        objects_collection = bpy.context.scene.splatter.objects_collection
        return objects_collection if objects_collection else bpy.context.scene.collection

    def get_group_name(self, obj: Any) -> Optional[str]:
        """Get the group name for an object from its collections."""
        for coll in getattr(obj, "users_collection", []) or []:
            if coll.name in self._managed_collection_names:
                return coll.name
        return None

    def iter_group_collections(self) -> Iterator[Any]:
        """Yield all collections that are in the managed collections set."""
        for coll_name in self._managed_collection_names:
            if coll_name in bpy.data.collections:
                yield bpy.data.collections[coll_name]

    def update_managed_group_names(self, group_names: list[str]) -> None:
        """Update the set of managed collection names by merging with existing names."""
        self._managed_collection_names.update(group_names)

    def get_managed_group_names_set(self) -> Set[str]:
        """Return the set of all managed collection names."""
        return self._managed_collection_names.copy()

    def has_existing_groups(self) -> bool:
        """Check if any groups exist."""
        return bool(self._managed_collection_names)

    def get_group_membership_snapshot(self) -> Dict[str, Set[str]]:
        """Return current group memberships from Blender collections."""
        snapshot = {}
        for coll in self.iter_group_collections():
            objects = getattr(coll, "objects", None) or []
            snapshot[coll.name] = {obj.name for obj in objects}
        return snapshot

    def _get_or_create_group_collection(self, obj: Any, group_name: str) -> Optional[Any]:
        """Get or create a collection for the group, commandeering existing collections if needed."""
        root_collection = self.get_objects_collection()
        # Check if this collection name is managed
        if group_name in self._managed_collection_names:
            # Search Blender's full collection list
            if group_name in bpy.data.collections:
                coll = bpy.data.collections[group_name]
                return coll

        # Handle collection-based groups
        # if group_name.endswith("_C"):
        top_coll = self._collection_manager.find_top_collection_for_object(obj, root_collection)
        if top_coll:
            top_coll.name = group_name
            return top_coll
        else:
            # Create new collection
            coll = bpy.data.collections.new(group_name)
            root_collection.children.link(coll)
            return coll


    def update_colors(self, sync_state: Dict[str, bool]) -> None:
        """Update color tags for collections based on sync state."""
        for coll in self.iter_group_collections():
            group_name = coll.name
            synced = sync_state.get(group_name, True)
            
            # 1. Determine the color that it *should* be.
            correct_color = 'COLOR_04' if synced else 'COLOR_03'
            
            # 2. Check if the collection's current color is already correct.
            if coll.color_tag != correct_color:
                # 3. Only perform the expensive write operation if it's wrong.
                coll.color_tag = correct_color

    def drop_group(self, group_name: str) -> None:
        """Drop a group from being managed: remove from managed set."""
        self._managed_collection_names.discard(group_name)

    def is_managed_collection(self, collection: Any) -> bool:
        """Check if the given collection is managed."""
        return collection.name in self._managed_collection_names

    # --- Convenience Methods ----------------------------------------------

    def ensure_group_collections(self, groups: list[list[Any]], group_names: list[str]) -> None:
        """Ensure group collections exist and assign objects to them with the specified color."""
        import time
        get_create_time = 0.0
        unlink_time = 0.0
        assign_time = 0.0
        
        for objects, group_name in zip(groups, group_names):
            if not objects:
                continue
            self._managed_collection_names.add(group_name)
            
            # Get or create the collection once
            get_create_start = time.perf_counter()
            group_collection = self._get_or_create_group_collection(objects[0], group_name)
            get_create_time += time.perf_counter() - get_create_start
            
            unlink_start = time.perf_counter()
            for obj in objects:
                self._collection_manager.ensure_object_unlink(self.get_objects_collection(), obj)
            unlink_time += time.perf_counter() - unlink_start
            
            # Assign all objects to the collection
            assign_start = time.perf_counter()
            self._collection_manager.assign_objects_to_collection(objects, group_collection)
            assign_time += time.perf_counter() - assign_start
        
        print(f"ensure_group_collections: get_create={get_create_time*1000:.1f}ms, unlink={unlink_time*1000:.1f}ms, assign={assign_time*1000:.1f}ms")

# Global instance
_group_manager = GroupManager()

def get_group_manager() -> GroupManager:
    """Get the global group manager instance."""
    return _group_manager