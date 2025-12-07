#include "shm_bridge.h"
#include <boost/interprocess/shared_memory_object.hpp>
#include <boost/interprocess/mapped_region.hpp>
#include <utility>
#include <new>

using namespace boost::interprocess;

SharedMemoryHandle create_segment(const char* name, size_t size) {
    // 1. Create the shared memory object (Boost Default Naming)
    shared_memory_object shm(create_only, name, read_write);
    
    // 2. Set the size
    shm.truncate(size);

    // 3. Map the region
    mapped_region region(shm, read_write);
    
    // 4. Create and return the handle (move ownership of Boost objects to the heap)
    auto shm_ptr = new shared_memory_object(std::move(shm));
    auto region_ptr = new mapped_region(std::move(region));

    return SharedMemoryHandle{ 
        region_ptr->get_address(), 
        size, 
        shm_ptr,
        region_ptr
    };
}

SharedMemoryHandle open_segment(const char* name) {
    shared_memory_object shm(open_only, name, read_write);
    mapped_region region(shm, read_write);
    
    auto shm_ptr = new shared_memory_object(std::move(shm));
    auto region_ptr = new mapped_region(std::move(region));

    return SharedMemoryHandle{ 
        region_ptr->get_address(), 
        region_ptr->get_size(), 
        shm_ptr,
        region_ptr
    };
}

void release_handle(SharedMemoryHandle* handle) {
    if (handle) {
        if (handle->internal_region_handle) {
            delete static_cast<mapped_region*>(handle->internal_region_handle);
            handle->internal_region_handle = nullptr;
        }
        if (handle->internal_shm_handle) {
            delete static_cast<shared_memory_object*>(handle->internal_shm_handle);
            handle->internal_shm_handle = nullptr;
        }
        handle->address = nullptr;
        handle->size = 0;
    }
}

void remove_segment(const char* name) {
    shared_memory_object::remove(name);
}
