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

# classification.pyx - C declarations and Python constants for classification

cdef extern from "classification.h":
    cdef int SurfaceType_Ground "static_cast<int>(SurfaceType::Ground)"
    cdef int SurfaceType_Wall "static_cast<int>(SurfaceType::Wall)"
    cdef int SurfaceType_Ceiling "static_cast<int>(SurfaceType::Ceiling)"
    cdef int SurfaceType_Unknown "static_cast<int>(SurfaceType::Unknown)"

# Expose enum values as Python constants using the imported C enum values
SURFACE_GROUND = SurfaceType_Ground
SURFACE_WALL = SurfaceType_Wall
SURFACE_CEILING = SurfaceType_Ceiling
SURFACE_UNKNOWN = SurfaceType_Unknown

# Also expose as a dict for easy lookup
SURFACE_TYPE_NAMES = {
    str(SurfaceType_Ground): "Ground Objects",
    str(SurfaceType_Wall): "Wall Objects",
    str(SurfaceType_Ceiling): "Ceiling Objects",
    str(SurfaceType_Unknown): "Unknown Objects"
}
