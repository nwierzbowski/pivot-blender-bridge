from libc.stdint cimport int32_t


cdef extern from "../engine/util.h" nogil:
    ctypedef struct Vec3:
        float x, y, z

    ctypedef struct Vec3i:
        int32_t x, y, z