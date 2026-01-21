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

__version__ = "1.0.0"

try:
    from . import edition_utils
    from . import engine_state
    from . import classification
    from . import collection_manager
    
    from . import group_manager
    from . import selection_utils
    from . import shm_utils
    
    from . import surface_manager
    from . import standardize
    from . import timer_manager
except ImportError as e:
    # Useful for debugging Blender console issues
    import warnings
    warnings.warn(f"Failed to load compiled Blender Bridge modules: {e}")


__all__ = [
    "classification",
    "collection_manager",
    "edition_utils",
    "engine_state",
    "group_manager",
    "selection_utils",
    "shm_utils",
    "standardize",
    "surface_manager",
    "timer_manager",
]
