# classification.pyx - C declarations and Python constants for classification

cdef extern from "classification.h":
    cdef int SurfaceType_Ground "static_cast<int>(SurfaceType::Ground)"
    cdef int SurfaceType_Wall "static_cast<int>(SurfaceType::Wall)"
    cdef int SurfaceType_Ceiling "static_cast<int>(SurfaceType::Ceiling)"

# Expose enum values as Python constants using the imported C enum values
SURFACE_GROUND = SurfaceType_Ground
SURFACE_WALL = SurfaceType_Wall
SURFACE_CEILING = SurfaceType_Ceiling

# Also expose as a dict for easy lookup
SURFACE_TYPE_NAMES = {
    SurfaceType_Ground: "Ground",
    SurfaceType_Wall: "Wall",
    SurfaceType_Ceiling: "Ceiling"
}

SURFACE_TYPE_ITEMS = [
    (str(SurfaceType_Ground), "Ground", "Ground surface"),
    (str(SurfaceType_Wall), "Wall", "Wall surface"),
    (str(SurfaceType_Ceiling), "Ceiling", "Ceiling surface"),
]
