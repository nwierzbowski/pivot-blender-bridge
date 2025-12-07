# distutils: language = c++
from libc.stddef cimport size_t
from cpython.buffer cimport Py_buffer
import uuid

cdef class SharedMemory:
    cdef SharedMemoryHandle _handle
    cdef str _name
    cdef bint _created
    cdef bint _closed
    cdef Py_ssize_t _shape[1]

    def __cinit__(self, str name=None, bint create=False, size_t size=0):
        self._closed = True
        if create:
            if name is None:
                # Generate a unique name if not provided
                self._name = "pshm_" + uuid.uuid4().hex
            else:
                self._name = name
            self._handle = create_segment(self._name.encode('utf-8'), size)
            self._created = True
            self._closed = False
        else:
            if name is None:
                raise ValueError("Name required when not creating")
            self._name = name
            self._handle = open_segment(self._name.encode('utf-8'))
            self._created = False
            self._closed = False
        self._shape[0] = <Py_ssize_t>self._handle.size

    def __dealloc__(self):
        if not self._closed:
            self.close()

    @property
    def buf(self):
        return memoryview(self)
    
    def __getbuffer__(self, Py_buffer *buffer, int flags):
        if self._closed:
            raise ValueError("Shared memory is closed")
            
        buffer.buf = self._handle.address
        buffer.len = self._handle.size
        buffer.readonly = 0
        buffer.itemsize = 1
        buffer.format = b"B"
        buffer.ndim = 1
        buffer.shape = self._shape
        buffer.strides = &buffer.itemsize
        buffer.suboffsets = NULL
        buffer.internal = NULL
        buffer.obj = self

    def __releasebuffer__(self, Py_buffer *buffer):
        pass

    def close(self):
        if not self._closed:
            release_handle(&self._handle)
            self._closed = True

    def unlink(self):
        remove_segment(self._name.encode('utf-8'))
        
    @property
    def name(self):
        return self._name
        
    @property
    def size(self):
        return self._handle.size
