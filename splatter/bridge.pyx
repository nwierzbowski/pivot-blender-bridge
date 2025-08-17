# cimport the C++ header file.
# The "nogil" means this function releases the Python Global Interpreter Lock,
# which is good practice for potentially long-running C++ code.
cdef extern from "engine.h" nogil:
    void say_hello_from_cpp()

# This is the Python function that your addon will actually call.
# It's a simple, clean wrapper around the C++ function.
def say_hello():
    """Calls the C++ function and prints a message from C++."""
    # We re-acquire the GIL if we need to do Python things before/after,
    # but for this simple call it's not strictly necessary.
    # It's good practice to show the pattern.
    with nogil:
        say_hello_from_cpp()