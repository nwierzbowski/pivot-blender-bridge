#pragma once
#include <cstddef>

// Forward-declare the handle struct
struct SharedMemoryHandle {
    void* address;
    size_t size;
    // Internal opaque pointers to manage the Boost object lifetime
    void* internal_shm_handle;
    void* internal_region_handle;
};

// Functions for creation and access, designed for Boost's default naming
SharedMemoryHandle create_segment(const char* name, size_t size);
SharedMemoryHandle open_segment(const char* name);
void release_handle(SharedMemoryHandle* handle);
void remove_segment(const char* name);
