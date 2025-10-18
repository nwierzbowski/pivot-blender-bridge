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

# Global instance
_group_manager = GroupManager()

def get_group_manager() -> GroupManager:
    """Get the global group manager instance."""
    return _group_manager