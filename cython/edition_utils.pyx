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

include "edition_flags.pxi" # type: ignore this exists in a generated file

# Expose edition flags as importable variables
cdef public int pivot_pro = PIVOT_EDITION_PRO # type: ignore this exists in a generated file
cdef public int pivot_standard = PIVOT_EDITION_STANDARD # type: ignore this exists in a generated file

def is_pro_edition() -> bool:
    return bool(PIVOT_EDITION_PRO)

def is_standard_edition() -> bool:
    return bool(PIVOT_EDITION_STANDARD)

def print_edition() -> None:
    """Print the edition this Cython module was compiled for (testing helper)."""
    if pivot_pro:
        print("[Pivot][Cython] Compile-time branch: PRO edition")
    elif pivot_standard:
        print("[Pivot][Cython] Compile-time branch: STANDARD edition")
    else:
        print("[Pivot][Cython] Compile-time branch: UNKNOWN edition")