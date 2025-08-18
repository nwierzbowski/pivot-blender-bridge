cdef extern from "../engine/util.h" nogil:
    ctypedef struct Vec3:
        float x
        float y
        float z