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

"""Low-level Blender collection management utilities.

Responsibilities:
- Create and manage Blender collections
- Handle collection linking and unlinking
- Collection hierarchy operations
"""

import bpy
from typing import TYPE_CHECKING, Any, Optional

if TYPE_CHECKING:  # pragma: no cover - Blender types only exist at runtime.
    from bpy.types import Collection, Object


class CollectionManager:
    """Handles low-level Blender collection operations."""

    def __init__(self) -> None:
        pass

    def get_or_create_root_collection(self, name: str) -> Optional[Any]:
        """Get or create a root collection linked to the scene."""
        scene = getattr(bpy.context, "scene", None)
        if not scene:
            return None

        root = bpy.data.collections.get(name) or bpy.data.collections.new(name)
        if scene.collection.children.find(root.name) == -1:
            scene.collection.children.link(root)
        return root

    def ensure_collection_link(self, parent: Any, child: Any) -> None:
        """Ensure child is linked to parent."""
        if not parent or not child:
            return
        
        # Check if already linked
        if parent.children.find(child.name) != -1:
            return
        
        try:
            parent.children.link(child)
        except RuntimeError as e:
            print(f"[ERROR] Failed to link {child.name} to {parent.name}: {e}")



    def find_top_collection_for_object(self, obj: Any, root_collection: Any) -> Optional[Any]:
        """Find the top-level collection containing the object."""
        for child in root_collection.children:
            if self.collection_contains_object(child, obj):
                return child
        return None

    def collection_contains_object(self, coll: Any, obj: Any) -> bool:
        """Check if collection contains object, recursively."""
        if coll in obj.users_collection:
            return True

        for child in coll.children:
            if self.collection_contains_object(child, obj):
                return True
        return False

    def assign_objects_to_collection(self, objects: list[Any], collection: Any) -> None:
        """Assign all objects to the collection."""
        for obj in objects:
            if collection not in obj.users_collection:
                collection.objects.link(obj)

    def ensure_object_unlink(self, collection: Any, obj: Any) -> None:
        """Ensure object is unlinked from collection."""
        if collection in obj.users_collection:
            collection.objects.unlink(obj)


# Global instance
_collection_manager = CollectionManager()

def get_collection_manager() -> CollectionManager:
    """Get the global collection manager instance."""
    return _collection_manager