"""Property management glue between Blender collections and the C++ engine.

Responsibilities:
- Track group metadata stored on Blender collections.
- Keep the expected engine state in sync with Blender edits.
- Provide a small, explicit API for callers to manage sync status.
"""

import bpy
from typing import TYPE_CHECKING, Any, Dict, Iterable, Iterator, Optional

from . import engine_state

# Command IDs for engine communication
COMMAND_SET_GROUP_CLASSIFICATIONS = 4


GROUP_COLLECTION_PROP = "splatter_group_name"
GROUP_COLLECTION_SYNC_PROP = "splatter_group_in_sync"

CLASSIFICATION_ROOT_COLLECTION_NAME = "Pivot"
CLASSIFICATION_COLLECTION_PROP = "splatter_surface_type"

if TYPE_CHECKING:  # pragma: no cover - Blender types only exist at runtime.
    from bpy.types import Collection, Object


class PropertyManager:
    """Centralized manager for object properties that handles engine synchronization."""

    def __init__(self) -> None:
        self._engine_communicator: Optional[Any] = None

    # --- Engine I/O helpers -------------------------------------------------

    def _get_engine_communicator(self) -> Optional[Any]:
        """Lazy-initialize and cache the engine communicator."""
        if self._engine_communicator is None:
            try:
                from .engine import get_engine_communicator
                self._engine_communicator = get_engine_communicator()
            except RuntimeError:
                self._engine_communicator = None
        return self._engine_communicator

    # --- Object/group helpers ----------------------------------------------

    def _get_group_name(self, obj: Any) -> Optional[str]:
        """Return the group's name by inspecting classification collections."""
        for coll in getattr(obj, "users_collection", []) or []:
            if getattr(coll, "get", None) is None:
                continue
            group = coll.get(GROUP_COLLECTION_PROP)
            if group:
                return group
        return None

    def get_group_name(self, obj: Any) -> Optional[str]:
        """Public accessor for group names backed by collections."""
        return self._get_group_name(obj)

    # --- Collection helpers ------------------------------------------------

    def _get_or_create_root_collection(self, name: str) -> Optional[Any]:
        scene = getattr(bpy.context, "scene", None)
        if scene is None:
            return None

        root = bpy.data.collections.get(name)
        if root is None:
            root = bpy.data.collections.new(name)
        if scene.collection.children.find(root.name) == -1:
            scene.collection.children.link(root)
        return root

    def _iter_child_collections(self, root: Any) -> Iterable[Any]:
        stack = list(getattr(root, "children", []) or [])
        while stack:
            coll = stack.pop()
            yield coll
            stack.extend(list(getattr(coll, "children", []) or []))

    def _collection_contains_object(self, coll: Any, obj: Any) -> bool:
        try:
            if coll.objects.find(obj.name) != -1:
                return True
        except (AttributeError, ReferenceError):
            return False

        for child in getattr(coll, "children", []) or []:
            if self._collection_contains_object(child, obj):
                return True
        return False

    def _find_top_collection_for_object(self, obj: Any, root_collection: Any) -> Optional[Any]:
        if root_collection is None:
            return None

        for child in getattr(root_collection, "children", []) or []:
            if self._collection_contains_object(child, obj):
                return child
        return None

    def _is_descendant_of(self, candidate: Any, root: Any) -> bool:
        if candidate is None or root is None or candidate == root:
            return False

        for coll in self._iter_child_collections(root):
            if coll == candidate:
                return True
        return False

    def _rename_collection(self, coll: Any, new_name: str) -> None:
        if getattr(coll, "name", None) == new_name:
            return

        existing = bpy.data.collections.get(new_name)
        if existing is not None and existing is not coll:
            return
        coll.name = new_name

    def _get_group_collection_for_object(self, obj: Any, group_name: Optional[str]) -> Optional[Any]:
        if not group_name:
            return None

        for coll in getattr(obj, "users_collection", []) or []:
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                return coll
        return None

    def _ensure_collection_link(self, parent: Any, child: Any) -> None:
        if parent is None or child is None:
            return

        children = getattr(parent, "children", None)
        if children is None:
            return

        if children.find(child.name) == -1:
            children.link(child)

    def _get_or_create_surface_collection(self, pivot_root: Any, surface_key: str) -> Optional[Any]:
        if pivot_root is None:
            return None

        for coll in pivot_root.children:
            if coll.get(CLASSIFICATION_COLLECTION_PROP) == surface_key:
                return coll

        # Attempt to reuse existing collection by name if available.
        existing = bpy.data.collections.get(surface_key)
        if existing is not None:
            self._ensure_collection_link(pivot_root, existing)
            existing[CLASSIFICATION_COLLECTION_PROP] = surface_key
            return existing

        surface_coll = bpy.data.collections.new(surface_key)
        surface_coll[CLASSIFICATION_COLLECTION_PROP] = surface_key
        pivot_root.children.link(surface_coll)
        return surface_coll

    def _tag_group_collection(self, coll: Any, group_name: str) -> None:
        """Ensure group metadata keys are populated on a collection."""
        coll[GROUP_COLLECTION_PROP] = group_name
        # Newly tagged collections are assumed to be in sync until explicitly invalidated.
        coll.setdefault(GROUP_COLLECTION_SYNC_PROP, True)
        # Set color tag based on sync status
        coll.color_tag = 'NONE' if coll.get(GROUP_COLLECTION_SYNC_PROP, True) else 'COLOR_03'

    def _get_or_create_group_collection(self, obj: Any, group_name: str, root_collection: Optional[Any]) -> Optional[Any]:
        """Return a collection under root_collection used for tracking group membership."""
        if root_collection is None:
            return None

        # Reuse any existing direct child collection tagged with this group.
        for coll in getattr(root_collection, "children", []) or []:
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                self._tag_group_collection(coll, group_name)
                return coll

        # If the root collection itself carries the group tag, reuse it.
        if root_collection.get(GROUP_COLLECTION_PROP) == group_name:
            self._tag_group_collection(root_collection, group_name)
            return root_collection

        # Collection-based groups (ending with "_C"): reuse the object's current top-level collection.
        if group_name.endswith("_C"):
            top_coll = self._find_top_collection_for_object(obj, root_collection)
            if top_coll is None:
                top_coll = bpy.data.collections.new(group_name)
                root_collection.children.link(top_coll)
            else:
                self._rename_collection(top_coll, group_name)

            self._tag_group_collection(top_coll, group_name)
            return top_coll

        # Parent-based groups: create or reuse a dedicated collection under the root.
        existing_named = bpy.data.collections.get(group_name)
        if existing_named is not None and self._is_descendant_of(existing_named, root_collection):
            self._tag_group_collection(existing_named, group_name)
            return existing_named

        coll = bpy.data.collections.new(group_name)
        self._tag_group_collection(coll, group_name)
        root_collection.children.link(coll)
        return coll

    def _iter_group_objects(self, group_name: str) -> Iterable[Any]:
        """Iterate over objects in collections tagged with the given group name."""
        for coll in bpy.data.collections:
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                # Return objects from the first matching collection (groups assumed unique)
                return iter(coll.objects)
        return iter([])

    def _unlink_other_group_collections(self, obj: Any, keep: Optional[Any]) -> None:
        to_unlink: list[Any] = []
        for coll in getattr(obj, "users_collection", []) or []:
            if coll.get(GROUP_COLLECTION_PROP) and coll is not keep:
                to_unlink.append(coll)
        for coll in to_unlink:
            try:
                coll.objects.unlink(obj)
            except RuntimeError:
                pass

    def _ensure_group_collection(self, obj: Any, group_name: Optional[str], fallback_name: str) -> Optional[Any]:
        """Ensure the object has a group collection, creating one if necessary."""
        group_collection = self._get_group_collection_for_object(obj, group_name)
        if group_collection is not None:
            return group_collection

        # Fallback: reuse or create a collection with the fallback name
        group_collection = bpy.data.collections.get(fallback_name)
        if group_collection is None:
            group_collection = bpy.data.collections.new(fallback_name)
        if group_collection not in obj.users_collection:
            group_collection.objects.link(obj)
        self._tag_group_collection(group_collection, group_name or fallback_name)
        return group_collection

    def _assign_surface_collection(self, obj: Any, surface_value: Any) -> None:
        surface_key = str(surface_value)
        pivot_root = self._get_or_create_root_collection(CLASSIFICATION_ROOT_COLLECTION_NAME)
        if pivot_root is None:
            return

        group_name = self._get_group_name(obj)
        group_collection = self._ensure_group_collection(obj, group_name, group_name or surface_key)

        surface_collection = self._get_or_create_surface_collection(pivot_root, surface_key)
        if surface_collection is None:
            return

        # Link the group collection under the correct surface classification branch.
        self._ensure_collection_link(surface_collection, group_collection)

        # Ensure the group collection's metadata reflects its latest surface type and
        # that it is not linked under any other surface containers.
        group_collection[CLASSIFICATION_COLLECTION_PROP] = surface_key
        self.mark_group_unsynced(group_collection.get(GROUP_COLLECTION_PROP))

        for coll in pivot_root.children:
            if coll is surface_collection:
                continue
            children = getattr(coll, "children", None)
            if children is None:
                continue
            if children.find(group_collection.name) != -1:
                children.unlink(group_collection)

    def collect_group_classifications(self) -> Dict[str, int]:
        """Collect current group -> surface classification mapping from Blender collections."""
        result: Dict[str, int] = {}
        pivot_root = bpy.data.collections.get(CLASSIFICATION_ROOT_COLLECTION_NAME)
        if pivot_root is None:
            return result

        for surface_coll in getattr(pivot_root, "children", []) or []:
            surface_value = surface_coll.get(CLASSIFICATION_COLLECTION_PROP)
            if surface_value is None:
                continue

            try:
                surface_int = int(surface_value)
            except (TypeError, ValueError):
                continue

            for group_coll in getattr(surface_coll, "children", []) or []:
                group_name = group_coll.get(GROUP_COLLECTION_PROP)
                if not group_name:
                    continue
                result[group_name] = surface_int

        return result

    def has_existing_groups(self) -> bool:
        """Check if there are any existing groups by looking at collection metadata."""
        return any(coll.get(GROUP_COLLECTION_PROP) for coll in bpy.data.collections)

    def sync_group_classifications(self, group_surface_map: Dict[str, Any]) -> bool:
        """Send a batch classification update to the engine."""
        if not group_surface_map:
            return True

        engine = self._get_engine_communicator()
        if not engine:
            return False

        classifications_payload = []
        normalized_map: Dict[str, int] = {}
        for name, value in group_surface_map.items():
            try:
                surface_int = int(value)
            except (TypeError, ValueError):
                continue
            classifications_payload.append({
                "group_name": name,
                "surface_type": surface_int
            })
            normalized_map[name] = surface_int

        if not classifications_payload:
            return True

        try:
            command = {
                "id": COMMAND_SET_GROUP_CLASSIFICATIONS,
                "op": "set_group_classifications",
                "classifications": classifications_payload
            }
            response = engine.send_command(command)
            if not response.get("ok", False):
                error = response.get("error", "Unknown error")
                print(f"Failed to update group classifications: {error}")
                return False

            for group_name, surface_int in normalized_map.items():
                self._update_engine_state(group_name, "surface_type", surface_int)
                self.mark_group_synced(group_name)
            return True
        except Exception as exc:
            print(f"Error sending group classifications: {exc}")
            return False

    def set_group_name(self, obj: Any, group_name: str, root_collection: Optional[Any] = None) -> bool:
        """Set group name for an object."""
        coll = self._get_or_create_group_collection(obj, group_name, root_collection)
        if coll is None:
            return False

        if coll not in obj.users_collection:
            coll.objects.link(obj)

        if root_collection is not None and root_collection is not coll:
            try:
                root_collection.objects.unlink(obj)
            except RuntimeError:
                pass

        self._unlink_other_group_collections(obj, coll)
        self.mark_group_unsynced(group_name)

        return True

    def _update_engine_state(self, group_name: str, attr_name: str, value: Any) -> None:
        """Update the expected engine state for a group attribute."""
        engine_state._engine_expected_state.setdefault(group_name, {})[attr_name] = value

    # --- Sync bookkeeping -------------------------------------------------

    def mark_group_unsynced(self, group_name: str) -> None:
        """Flag every collection representing the group as needing an engine refresh."""
        if not group_name:
            return

        for coll in self.iter_group_collections():
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                coll[GROUP_COLLECTION_SYNC_PROP] = False
                coll.color_tag = 'COLOR_03'

    def mark_group_synced(self, group_name: str) -> None:
        """Mark all collections for the group as synchronized with the engine."""
        if not group_name:
            return

        for coll in self.iter_group_collections():
            if coll.get(GROUP_COLLECTION_PROP) == group_name:
                coll[GROUP_COLLECTION_SYNC_PROP] = True
                coll.color_tag = 'NONE'

    def iter_group_collections(self) -> Iterator[Any]:
        """Yield every Blender collection tagged as a group collection."""
        for coll in bpy.data.collections:
            if coll.get(GROUP_COLLECTION_PROP):
                yield coll

    def iter_unsynced_group_collections(self) -> Iterator[Any]:
        """Yield group collections flagged as out-of-sync with the engine."""
        for coll in self.iter_group_collections():
            if not coll.get(GROUP_COLLECTION_SYNC_PROP, True):
                yield coll

    def get_group_collections(self) -> list[Any]:
        """Return all group collections as a materialized list."""
        return list(self.iter_group_collections())

    def get_unsynced_group_collections(self) -> list[Any]:
        """Return every group collection flagged as out-of-sync."""
        return list(self.iter_unsynced_group_collections())

    # Global instance
_property_manager = PropertyManager()

def get_property_manager() -> PropertyManager:
    """Get the global property manager instance."""
    return _property_manager
