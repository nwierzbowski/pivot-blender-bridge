# GitHub Actions Build Matrix Setup Guide

## Platform/Architecture Coverage

Your GitHub Actions workflow should build for these configurations:

### Linux
```
✅ Ubuntu 22.04 LTS (x86-64) - ubuntu-latest
✅ Ubuntu 24.04 ARM64          - ubuntu-24.04-arm (if available)
   OR use custom arm64 runner
```

### macOS  
```
✅ macOS 14 (Sonoma) x86-64    - macos-13
✅ macOS 14 (Sonoma) arm64     - macos-14 (Apple Silicon)
```

### Windows
```
✅ Windows Server 2022 x86-64  - windows-latest
   Windows arm64 (optional)    - windows-latest-arm (if needed)
```

---

## Build Configurations

Each platform should build **both editions**:

| Edition | Target | Binary Name |
|---------|--------|------------|
| **PRO** | All platforms | `splatter_engine` (or `.exe` on Windows) |
| **STANDARD** | All platforms | `splatter_engine` (or `.exe` on Windows) |

---

## Expected Output Structure

After all CI builds complete, artifacts should be organized as:

```
splatter-engine-binaries/
├── linux-x64/
│   ├── pro/
│   │   └── splatter_engine
│   └── standard/
│       └── splatter_engine
├── linux-arm64/
│   ├── pro/
│   │   └── splatter_engine
│   └── standard/
│       └── splatter_engine
├── macos-x64/
│   ├── pro/
│   │   └── splatter_engine
│   └── standard/
│       └── splatter_engine
├── macos-arm64/
│   ├── pro/
│   │   └── splatter_engine
│   └── standard/
│       └── splatter_engine
├── windows-x64/
│   ├── pro/
│   │   └── splatter_engine.exe
│   └── standard/
│       └── splatter_engine.exe
└── manifest.json  # List of all binaries built
```

### Alternative Simpler Structure

If the above is too complex, flatten it to:

```
artifacts/
├── splatter_engine-linux-x64-pro
├── splatter_engine-linux-x64-standard
├── splatter_engine-linux-arm64-pro
├── splatter_engine-linux-arm64-standard
├── splatter_engine-macos-x64-pro
├── splatter_engine-macos-x64-standard
├── splatter_engine-macos-arm64-pro
├── splatter_engine-macos-arm64-standard
├── splatter_engine-windows-x64-pro.exe
└── splatter_engine-windows-x64-standard.exe
```

---

## Per-Platform Build Notes

### 🐧 Linux (Ubuntu 22.04 LTS, x86-64)

**Runner:** `ubuntu-latest`

**Setup Steps:**
```bash
# Install build dependencies
sudo apt update
sudo apt install -y \
    cmake \
    ninja-build \
    g++ \
    python3-dev \
    python3-pip \
    cython3 \
    python3-numpy

# Install CMake and Ninja (usually pre-installed on GitHub Actions)
# But verify in workflow

pip3 install --user cython numpy
```

**Build Commands:**
```bash
cmake --preset=pro
cmake --build --preset=pro-release
cmake --preset=standard
cmake --build --preset=standard-release
```

**Verify:**
```bash
file splatter/bin/splatter_engine
ldd splatter/bin/splatter_engine
# Expected: Only libc.so.6, libm.so.6, ld-linux-x86-64.so.2
```

**Binary Size:** ~1.9MB (static linked)

---

### 🐧 Linux (Ubuntu 24.04, arm64)

**Runner:** `ubuntu-24.04-arm` (GitHub-hosted)
OR custom self-hosted arm64 runner

**Setup:** Same as x86-64

**Build:** Same commands

**Verify:**
```bash
file splatter/bin/splatter_engine
# Expected: ELF 64-bit LSB pie executable, ARM aarch64
```

---

### 🍎 macOS (Intel x86-64)

**Runner:** `macos-13` or `macos-14` (Intel runner)

**Setup Steps:**
```bash
# Homebrew should be pre-installed
brew install cmake ninja python cython numpy

# Verify installations
cmake --version
ninja --version
python3 --version
cython --version
```

**Build Commands:**
```bash
cmake --preset=pro
cmake --build --preset=pro-release
cmake --preset=standard
cmake --build --preset=standard-release
```

**Verify:**
```bash
file splatter/bin/splatter_engine
otool -L splatter/bin/splatter_engine
# Expected: Minimal dylib dependencies (system libs only)
```

**Binary Size:** ~2.0-2.5MB (may vary)

---

### 🍎 macOS (Apple Silicon arm64)

**Runner:** `macos-14` (Apple Silicon native runner)

**Setup:** Same as Intel macOS

**Build:** Same commands

**Verify:**
```bash
file splatter/bin/splatter_engine
# Expected: Mach-O 64-bit executable arm64
otool -L splatter/bin/splatter_engine
```

---

### 🪟 Windows (x86-64)

**Runner:** `windows-latest`

**Setup Steps:**
```batch
# Use pre-installed MSVC and CMake
# If needed:
choco install cmake ninja python

# Or use vcpkg (if you prefer)
```

**Build Commands:**
```batch
cmake --preset=pro
cmake --build --preset=pro-release
cmake --preset=standard
cmake --build --preset=standard-release
```

**Verify:**
```batch
file splatter\bin\splatter_engine.exe
# Or use:
dumpbin /dependents splatter\bin\splatter_engine.exe
# Expected: Only kernel32.dll, msvcrt.dll (system libs)
```

**Binary Size:** ~2.5-3.0MB

**Notes:**
- Windows may need `CMAKE_PREFIX_PATH` set if using system Boost
- Most likely will use FetchContent for Boost (recommended)
- Static MSVC CRT ensures portability across Windows versions

---

## Workflow Performance Expectations

### First Build (with dependency fetch)
- **Linux:** ~8-12 minutes (Boost fetch ~4-5 min)
- **macOS:** ~10-15 minutes (Boost fetch + compile time)
- **Windows:** ~12-18 minutes (MSVC compile slower)

### Subsequent Builds (cached dependencies)
- **Linux:** ~3-4 minutes
- **macOS:** ~4-5 minutes  
- **Windows:** ~5-7 minutes

**Total for full matrix (first run):** ~60-90 minutes
**Subsequent runs:** ~25-35 minutes

---

## GitHub Actions Cache Strategy

Add this to your workflow to cache CMake builds and dependencies:

```yaml
- uses: actions/cache@v4
  with:
    path: |
      build-pro
      build-standard
      ~/.conan/data
    key: ${{ runner.os }}-${{ runner.arch }}-cmake-${{ hashFiles('CMakeLists.txt') }}
    restore-keys: |
      ${{ runner.os }}-${{ runner.arch }}-cmake-
```

This caches:
- Build artifacts (object files, intermediate files)
- Fetched dependencies (Boost, Eigen)
- Significantly speeds up rebuild times

---

## Troubleshooting Common CI Issues

### Issue: Python not found on Ubuntu
**Solution:** 
```bash
apt install python3-dev python3-pip
pip3 install cython numpy
```

### Issue: Boost fetch timeout
**Solution:** 
- GitHub Actions has good network, shouldn't happen
- If it does, retry workflow (transient network issue)
- Can pre-download Boost and cache it

### Issue: macOS build fails with "unknown platform"
**Solution:**
- Ensure correct macOS runner selected
- Verify Python 3 is available
- Check if homebrew packages need update

### Issue: Windows build fails with MSVC errors
**Solution:**
- May need to run from "Developer Command Prompt"
- Ensure Visual Studio/Build Tools installed
- Check `CMAKE_GENERATOR` is set to correct MSVC version

### Issue: Binary size unexpectedly large
**Possible causes:**
- Debug symbols included (shouldn't happen with Release config)
- Static linking working correctly
- Inspect with `nm -C` to verify symbols are present

---

## Release Strategy

After all platform builds complete:

1. **Download all artifacts** from GitHub Actions
2. **Create versioned release** with naming: `v0.1.0` (or your version)
3. **Upload binaries** to release with platform-specific folder structure
4. **Update addon's `engine.py`** to download correct binary for user's OS/arch at runtime
5. **Alternative:** Package binaries inside addon ZIP for distribution

---

## Next Steps

1. ✅ CMake build system is ready (you just fixed it)
2. ⏭️  Create `.github/workflows/build.yml` with the matrix above
3. ⏭️  Test on feature branch before merging to main
4. ⏭️  Verify artifacts are generated correctly
5. ⏭️  Set up release automation
6. ⏭️  Update `splatter/engine.py` to detect and use correct binary

---

## Quick Workflow Template

See the next document: `.github/workflows/build.yml` for complete workflow configuration.
