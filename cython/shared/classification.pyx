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
    str(SurfaceType_Ground): "Ground Objects",
    str(SurfaceType_Wall): "Wall Objects",
    str(SurfaceType_Ceiling): "Ceiling Objects"
}

# SURFACE_TYPE_ITEMS = [
#     (str(SurfaceType_Ground), "Ground", "Object belongs on the ground"),
#     (str(SurfaceType_Wall), "Wall", "Object belongs on the wall"),
#     (str(SurfaceType_Ceiling), "Ceiling", "Object belongs on the ceiling"),
# ]
