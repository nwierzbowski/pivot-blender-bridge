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

"""Engine State Management

Hosts global state that describes what the external C++ engine currently 
believes about the scene. Keeping this module slim makes it easy to reason 
about how Blender-side edits diverge from the engine.
"""

# Flag to indicate if classification is in progress
cdef bint _is_performing_classification = False

# ---------------------------------------------------------------------------
# Classification flag helpers
# ---------------------------------------------------------------------------

def set_performing_classification(bint value) -> None:
    """Set whether classification is currently in progress."""
    global _is_performing_classification
    _is_performing_classification = value


def is_performing_classification() -> bint:
    """Check if classification is currently in progress."""
    return _is_performing_classification

