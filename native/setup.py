#!/usr/bin/env python3
# Copyright (C) 2025 Nicholas Wierzbowski / Elbo Studio
# This file is part of the Pivot Bridge for Blender.
#
# Minimal setup.py for platform-specific wheels with pre-compiled Cython extensions.

import os
import platform
from pathlib import Path
from setuptools import setup
from setuptools.dist import Distribution


class BinaryDistribution(Distribution):
    """Distribution that always builds platform-specific wheels."""
    def has_ext_modules(self):
        return True


def get_package_data():
    """Find all pre-compiled extension modules for package_data."""
    pkg_dir = Path(__file__).parent
    ext_suffix = ".pyd" if platform.system() == "Windows" else ".so"
    
    so_files = [f.name for f in pkg_dir.glob(f"*{ext_suffix}")]
    return {"pivot_lib": so_files}


setup(
    distclass=BinaryDistribution,
    package_data=get_package_data(),
)
