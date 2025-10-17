"""Synchronization state management for engine operations.

Responsibilities:
- Track sync status of groups with the C++ engine
- Manage sync state in memory (avoids Blender undo conflicts)
"""

from typing import Dict

from splatter.group_manager import get_group_manager


cdef class SyncManager:
    """Manages synchronization state between Blender and the C++ engine.
    
    Tracks which groups need syncing using in-memory state only.
    This keeps sync state separate from Blender's undo system.
    """

    cdef dict _sync_state

    def __init__(self) -> None:
        # Maps group_name -> bool (True = synced, False = unsynced)
        self._sync_state = {}

    cpdef void set_group_unsynced(self, str group_name):
        """Remember that a group needs a round-trip to the engine."""
        if group_name:
            self._sync_state[group_name] = False

    cpdef void set_group_synced(self, str group_name):
        """Mark a group as synced with the engine."""
        if group_name:
            self._sync_state[group_name] = True
    
    cpdef void set_groups_synced(self, object group_names):
        """Mark multiple groups as synced with the engine."""
        cdef str name
        for name in group_names:
            if name:
                self._sync_state[name] = True
        
    cpdef set get_unsynced_groups(self):
        """Return a set of group names that are out of sync."""
        return {name for name, synced in self._sync_state.items() if not synced}

    cpdef dict organize_groups_into_surfaces(self, list full_groups, list group_names, list surface_types, object parent_collection):
        """Create group collections, set colors, and mark as synced. Returns group_collections for further processing."""
        group_manager = get_group_manager()
        
        # Build mapping of group collections and surface assignments
        group_collections = {}
        
        for idx, group in enumerate(full_groups):
            group_name = group_names[idx]
            
            # Create group collection
            group_coll = group_manager.create_or_get_group_collection(group, group_name, parent_collection)
            if group_coll:
                group_collections[group_name] = group_coll
        
        # Set colors for all created groups
        group_manager.set_group_colors(list(group_collections.keys()))
        
        # Mark groups as synced after successful creation
        self.set_groups_synced(group_names)
        
        return group_collections


# Global instance
cdef SyncManager _sync_manager = SyncManager()

cpdef SyncManager get_sync_manager():
    """Get the global sync manager instance."""
    return _sync_manager