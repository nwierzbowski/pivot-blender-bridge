# Property Management System
# Centralized management of object properties with automatic engine synchronization

import bpy
from typing import Any, Optional

from . import engine_state

# Command IDs for engine communication
COMMAND_SET_GROUP_ATTR = 2
COMMAND_SYNC_OBJECT = 3


class PropertyManager:
    """Centralized manager for object properties that handles engine synchronization."""

    def __init__(self) -> None:
        self._engine_communicator: Optional[Any] = None

    def _get_engine_communicator(self) -> Optional[Any]:
        """Lazy initialization of engine communicator."""
        if self._engine_communicator is None:
            try:
                from .engine import get_engine_communicator
                self._engine_communicator = get_engine_communicator()
            except RuntimeError:
                self._engine_communicator = None
        return self._engine_communicator

    def set_attribute(self, obj: Any, attr_name: str, engine_value: Any, update_group: bool = True, update_engine: bool = True) -> bool:
        """
        Set an attribute for an object with optional group and engine updates.

        Args:
            obj: Blender object.
            attr_name: Name of the attribute (e.g., 'surfaceType').
            engine_value: Value to send to engine (converted to Blender value internally).
            update_group: Whether to update all objects in the same group.
            update_engine: Whether to sync with the engine.

        Returns:
            bool: True if successful, False otherwise.
        """
        if not hasattr(obj, 'classification'):
            return False

        # Convert engine value to Blender value
        blender_value = str(engine_value) if isinstance(engine_value, int) else engine_value

        group_name = obj.classification.group_name

        # Handle group update with engine sync
        if update_group and update_engine and group_name:
            if not self._send_group_attribute_command(group_name, attr_name, engine_value):
                return False

        # Update the object's property
        if getattr(obj.classification, attr_name, None) != blender_value:
            setattr(obj.classification, attr_name, blender_value)

        # Update group properties if requested
        if update_group and group_name:
            self._update_group_attribute(obj, attr_name, blender_value, engine_value)
            self._update_engine_state(group_name, attr_name, engine_value)
        elif update_engine and group_name:
            self._update_engine_state(group_name, attr_name, engine_value)

        return True

    def _send_group_attribute_command(self, group_name: str, attr_name: str, engine_value: Any) -> bool:
        """Send command to engine to set group attribute."""
        engine = self._get_engine_communicator()
        if not engine:
            return False

        try:
            command = {
                "id": COMMAND_SET_GROUP_ATTR,
                "op": "set_group_attr",
                "group_name": group_name,
                "attr": attr_name,
                "value": engine_value
            }
            response = engine.send_command(command)
            if "ok" not in response or not response["ok"]:
                print(f"Failed to update engine group {attr_name}: {response.get('error', 'Unknown error')}")
                return False
            return True
        except Exception as e:
            print(f"Error updating engine group {attr_name}: {e}")
            return False

    def set_group_name(self, obj: Any, group_name: str) -> bool:
        """Set group name for an object.

        Args:
            obj: Blender object.
            group_name: Name of the group.

        Returns:
            bool: True if successful, False otherwise.
        """
        if hasattr(obj, 'classification'):
            obj.classification.group_name = group_name
            return True
        return False

    def _update_engine_state(self, group_name: str, attr_name: str, value: Any) -> None:
        """Update the expected engine state for a group attribute.

        Args:
            group_name: Name of the group.
            attr_name: Name of the attribute.
            value: The expected value.
        """
        engine_state._engine_expected_state.setdefault(group_name, {})[attr_name] = value

    def _update_group_attribute(self, source_obj: Any, attr_name: str, blender_value: Any, engine_value: Any) -> None:
        """Update all objects in the same group as the source object for a given attribute.

        Args:
            source_obj: The source Blender object.
            attr_name: Name of the attribute.
            blender_value: Value to set in Blender.
            engine_value: Value for engine (unused here).
        """
        group_name = source_obj.classification.group_name
        if not group_name:
            return

        # Update all other objects in the group (skip the source object)
        for obj in bpy.context.scene.objects:
            if (obj != source_obj and
                hasattr(obj, 'classification') and
                hasattr(obj.classification, 'group_name') and
                obj.classification.group_name == group_name):

                # Update the property directly to avoid triggering callbacks
                if getattr(obj.classification, attr_name, None) != blender_value:
                    setattr(obj.classification, attr_name, blender_value)

    def sync_object_properties(self, obj: Any) -> int:
        """
        Sync all properties that need synchronization for the object.

        Args:
            obj: Blender object.

        Returns:
            int: Number of properties that were synced.
        """
        synced_count = 0
        for attr_name in get_syncable_properties():
            if self.needs_attribute_sync(obj, attr_name):
                if self.sync_attribute_with_engine(obj, attr_name):
                    synced_count += 1
        return synced_count

    def sync_attribute_with_engine(self, obj: Any, attr_name: str) -> bool:
        """
        Sync a single object's attribute with the engine.

        Args:
            obj: Blender object.
            attr_name: Name of the attribute.

        Returns:
            bool: True if sync was successful, False otherwise.
        """
        if not (hasattr(obj, 'classification') and
                hasattr(obj.classification, 'group_name') and
                obj.classification.group_name):
            return False

        engine = self._get_engine_communicator()
        if not engine:
            return False

        try:
            group_name = obj.classification.group_name
            value = getattr(obj.classification, attr_name)


            command = {
                "id": COMMAND_SYNC_OBJECT,
                "op": "set_group_attr",
                "group_name": group_name,
                "attr": attr_name,
                "value": value
            }

            response = engine.send_command(command)
            if response.get("ok"):
                self._update_engine_state(group_name, attr_name, value)
                return True
            else:
                print(f"Failed to sync {obj.name} {attr_name}: {response.get('error', 'Unknown error')}")

        except Exception as e:
            print(f"Error syncing {obj.name} {attr_name}: {e}")

        return False

    def needs_attribute_sync(self, obj: Any, attr_name: str) -> bool:
        """Check if an object needs attribute synchronization.

        Args:
            obj: Blender object.
            attr_name: Name of the attribute.

        Returns:
            bool: True if sync is needed, False otherwise.
        """
        if not (hasattr(obj, 'classification') and
                hasattr(obj.classification, 'group_name') and
                hasattr(obj.classification, attr_name)):
            return False

        # Only sync objects that have been processed by align_to_axes
        if not obj.classification.group_name:
            return False

        try:
            current_value = getattr(obj.classification, attr_name)
            expected_value = engine_state._engine_expected_state.get(obj.classification.group_name, {}).get(attr_name)
            return expected_value is not None and current_value != expected_value
        except (ValueError, AttributeError):
            return False

    def needs_sync(self, obj: Any) -> bool:
        """Check if any property needs synchronization for the object.

        Args:
            obj: Blender object.

        Returns:
            bool: True if any sync is needed, False otherwise.
        """
        for attr_name in get_syncable_properties():
            if self.needs_attribute_sync(obj, attr_name):
                return True
        return False

    def needs_surface_sync(self, obj: Any) -> bool:
        """Check if an object needs surface type synchronization.

        Args:
            obj: Blender object.

        Returns:
            bool: True if sync is needed, False otherwise.
        """
        return self.needs_attribute_sync(obj, 'surface_type')


def get_syncable_properties() -> list[str]:
    """Get the list of syncable properties from ObjectAttributes, excluding group_name."""
    from .classes import ObjectAttributes
    syncable_props = [name for name in ObjectAttributes.__annotations__ if name != 'group_name']
    return syncable_props


# Global instance
_property_manager = PropertyManager()

def get_property_manager() -> PropertyManager:
    """Get the global property manager instance."""
    return _property_manager
