# type: ignore
from bpy.types import PropertyGroup, Collection
from bpy.props import BoolProperty, EnumProperty, StringProperty, PointerProperty
import bpy

# Import C enum values from Cython module
from .lib import classification
from .constants import LICENSE_STANDARD, LICENSE_PRO

# UI Labels (property names derived from these)
LABEL_OBJECTS_COLLECTION = "Objects:"
LABEL_ROOM_COLLECTION = "Room:"
LABEL_SURFACE_TYPE = "Surface:"
LABEL_LICENSE_TYPE = "License:"

# Marker property to identify classification collections
CLASSIFICATION_MARKER_PROP = "splatter_is_classification_collection"

def poll_visible_collections(self, coll):
    """
    Only show collections that are NOT marked as 'is_internal_collection'.
    We use .get() to avoid an error if the property doesn't exist.
    """
    return not coll.get(CLASSIFICATION_MARKER_PROP, False)


class SceneAttributes(PropertyGroup):
    objects_collection: PointerProperty(
        name=LABEL_OBJECTS_COLLECTION.rstrip(":"),
        description="Collection containing objects to scatter",
        type=Collection,
        poll=poll_visible_collections,
    )
    room_collection: PointerProperty(
        name=LABEL_ROOM_COLLECTION.rstrip(":"),
        description="Collection containing room geometry",
        type=Collection,
        poll=poll_visible_collections,
    )
    license_type: StringProperty(
        name=LABEL_LICENSE_TYPE.rstrip(":"),
        description="License type (read-only, determined by engine)",
        default="UNKNOWN",
    )
