"""Group management for Blender collections.

Responsibilities:
- Manage group collections and their metadata
- Handle group membership operations
- Provide group-related queries and utilities
"""

import bpy
from typing import TYPE_CHECKING, Any, Dict, Iterator, Optional, Set

from .collection_manager import get_collection_manager

# Property keys for collection metadata
GROUP_COLLECTION_PROP = "splatter_group_name"

if TYPE_CHECKING:  # pragma: no cover - Blender types only exist at runtime.
    from bpy.types import Collection, Object


class GroupManager:
    """Manages group collections and their metadata."""

    def __init__(self) -> None:
        self._collection_manager = get_collection_manager()

    def get_group_name(self, obj: Any) -> Optional[str]:
        """Get the group name for an object from its collections."""
        for coll in getattr(obj, "users_collection", []) or []:
            if group := coll.get(GROUP_COLLECTION_PROP):
                return group
        return None

    def iter_group_collections(self) -> Iterator[Any]:
        """Yield all collections tagged as group collections."""
        for coll in bpy.data.collections:
            if coll.get(GROUP_COLLECTION_PROP):
                yield coll

    def get_managed_group_names(self) -> list[str]:
        """Return sorted list of all managed group names."""
        names = {coll.get(GROUP_COLLECTION_PROP) for coll in self.iter_group_collections()}
        return sorted(name for name in names if name)

    def has_existing_groups(self) -> bool:
        """Check if any groups exist."""
        return any(self.iter_group_collections())

    def get_group_membership_snapshot(self) -> Dict[str, Set[str]]:
        """Return current group memberships from Blender collections."""
        snapshot = {}
        for coll in self.iter_group_collections():
            if group_name := coll.get(GROUP_COLLECTION_PROP):
                objects = getattr(coll, "objects", None) or []
                snapshot[group_name] = {obj.name for obj in objects}
        return snapshot

    def _get_or_create_group_collection(self, obj: Any, group_name: str, root_collection: Optional[Any]) -> Optional[Any]:
        """Get or create a collection for the group."""
        if not root_collection:
            return None

        # Check for existing tagged child
        for coll in root_collection.children:
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                self._tag_group_collection(coll, group_name)
                return coll

        # Handle collection-based groups
        if group_name.endswith("_C"):
            top_coll = self._collection_manager.find_top_collection_for_object(obj, root_collection)
            if not top_coll:
                top_coll = bpy.data.collections.new(group_name)
                root_collection.children.link(top_coll)
            else:
                top_coll.name = group_name
            self._tag_group_collection(top_coll, group_name)
            return top_coll

        # Create new collection
        coll = bpy.data.collections.new(group_name)
        self._tag_group_collection(coll, group_name)
        root_collection.children.link(coll)
        return coll

    def _tag_group_collection(self, coll: Any, group_name: str) -> None:
        """Tag a collection with group metadata."""
        coll[GROUP_COLLECTION_PROP] = group_name

    def set_group_colors(self, group_names: list[str], color: str = 'COLOR_04') -> None:
        """Set the color tag for collections of the specified group names."""
        for coll in self.iter_group_collections():
            if coll.get(GROUP_COLLECTION_PROP) in group_names:
                coll.color_tag = color

    def iter_group_objects(self, group_name: str) -> Iterator[Any]:
        """Iterate over objects in collections tagged with the given group name."""
        for coll in self.iter_group_collections():
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                # Return objects from the first matching collection (groups assumed unique)
                return iter(coll.objects)
        return iter([])

    def drop_group(self, group_name: str) -> None:
        """Drop a group from being managed: reset color and remove group tag."""
        for coll in self.iter_group_collections():
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                coll.color_tag = 'NONE'
                del coll[GROUP_COLLECTION_PROP]
                break

    # --- Convenience Methods ----------------------------------------------

    def group_in_outliner(self, groups: list[list[Any]], group_names: list[str], root_collection: Optional[Any] = None) -> None:
        """Create or get multiple group collections and assign objects to them."""
        for objects, group_name in zip(groups, group_names):
            if not objects or not root_collection:
                continue
            
            # Get or create the collection once
            group_collection = self._get_or_create_group_collection(objects[0], group_name, root_collection)
            if not group_collection:
                continue
            
            # Assign all objects to the collection
            self._assign_objects_to_collection(objects, group_collection, root_collection)

    def _assign_objects_to_collection(self, objects: list[Any], group_collection: Any, root_collection: Optional[Any]) -> None:
        """Assign all objects to the collection."""
        for obj in objects:
            if group_collection not in obj.users_collection:
                group_collection.objects.link(obj)
            
            if root_collection and root_collection is not group_collection:
                try:
                    root_collection.objects.unlink(obj)
                except RuntimeError:
                    pass

    def get_all_group_collections(self) -> Dict[str, Any]:
        """Get a dict of group_name -> collection for all current group collections."""
        return {coll.get(GROUP_COLLECTION_PROP): coll for coll in self.iter_group_collections() if coll.get(GROUP_COLLECTION_PROP)}

    def get_group_collections_for_names(self, group_names: list[str]) -> Dict[str, Any]:
        """Get a dict of group_name -> collection for the specified group names."""
        result = {}
        for coll in self.iter_group_collections():
            if group_name := coll.get(GROUP_COLLECTION_PROP):
                if group_name in group_names:
                    result[group_name] = coll
        return result


# Global instance
_group_manager = GroupManager()

def get_group_manager() -> GroupManager:
    """Get the global group manager instance."""
    return _group_manager