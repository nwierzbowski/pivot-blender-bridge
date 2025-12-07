from libc.stddef cimport size_t

cdef extern from "shm_bridge.h":
    cdef struct SharedMemoryHandle:
        void* address
        size_t size
        void* internal_shm_handle
        void* internal_region_handle

    SharedMemoryHandle create_segment(const char* name, size_t size) except +
    SharedMemoryHandle open_segment(const char* name) except +
    void release_handle(SharedMemoryHandle* handle) except +
    void remove_segment(const char* name) except +
