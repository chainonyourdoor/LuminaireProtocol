#!/usr/bin/env bash

# ======================================================
# 🩹 ADDON — KPatch-Next
# Kernel patch/hook framework (KPM module support)
# Repo: https://github.com/KernelSU-Next/KPatch-Next
# ======================================================

KPATCH_NEXT_REPO="https://github.com/KernelSU-Next/KPatch-Next.git"
KPATCH_NEXT_SRC_DIR="${WORKSPACE_DIR}/kpatch-next"
KPATCH_NEXT_SRC_CACHE_DIR="${HOME}/kpatch-next-src-cache"

log "🩹 Fetching KPatch-Next source..."

if [ -d "${KPATCH_NEXT_SRC_CACHE_DIR}/.git" ]; then
    log "KPatch-Next: restoring source from cache..."
    rm -rf "${KPATCH_NEXT_SRC_DIR}"
    cp -a "${KPATCH_NEXT_SRC_CACHE_DIR}" "${KPATCH_NEXT_SRC_DIR}"
else
    rm -rf "${KPATCH_NEXT_SRC_DIR}"
    retry 3 run_quiet git clone -q --depth=1 "${KPATCH_NEXT_REPO}" "${KPATCH_NEXT_SRC_DIR}" \
        || error "KPatch-Next: failed to clone source!"
    log "KPatch-Next: saving source to cache..."
    mkdir -p "${KPATCH_NEXT_SRC_CACHE_DIR}"
    cp -a "${KPATCH_NEXT_SRC_DIR}/." "${KPATCH_NEXT_SRC_CACHE_DIR}/"
fi

[ -d "${KPATCH_NEXT_SRC_DIR}/kernel" ] && [ -d "${KPATCH_NEXT_SRC_DIR}/tools" ] && [ -d "${KPATCH_NEXT_SRC_DIR}/user" ] \
    || error "KPatch-Next: cloned repo missing kernel/tools/user — layout may have changed upstream!"

# ---------------------------------------------------------
# Bare-metal aarch64-none-elf toolchain (required for kpimg —
# aarch64-linux-gnu- from TOOL_CROSS_COMPILE will NOT work here,
# kpimg is a freestanding ELF, not a userspace/kernel-module binary)
#
# This cache dir + the NDK one below are restored/saved by the
# "Cache KPatch-Next Toolchains" actions/cache step in build.yml —
# this script only needs to check whether they're already populated.
# ---------------------------------------------------------

KPATCH_TOOLCHAIN_DIR="${ROOT_DIR}/kpatch-toolchain"
KPATCH_TOOLCHAIN_CACHE_DIR="${HOME}/kpatch-toolchain-cache"
# NOTE: pinned version — bump deliberately, verify it still extracts to
# a bin/ with aarch64-none-elf-gcc before trusting a version bump.
KPATCH_TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-elf.tar.xz"

if [ -d "${KPATCH_TOOLCHAIN_CACHE_DIR}/bin" ]; then
    log "KPatch-Next: restoring aarch64-none-elf toolchain from cache..."
    mkdir -p "$KPATCH_TOOLCHAIN_DIR"
    cp -a "${KPATCH_TOOLCHAIN_CACHE_DIR}/." "${KPATCH_TOOLCHAIN_DIR}/"
    if ! "${KPATCH_TOOLCHAIN_DIR}/bin/aarch64-none-elf-gcc" --version > /dev/null 2>&1; then
        warn "KPatch-Next: cached toolchain broken — re-downloading..."
        rm -rf "$KPATCH_TOOLCHAIN_DIR" "$KPATCH_TOOLCHAIN_CACHE_DIR"
    fi
fi

if [ ! -x "${KPATCH_TOOLCHAIN_DIR}/bin/aarch64-none-elf-gcc" ]; then
    log "KPatch-Next: downloading aarch64-none-elf toolchain..."
    mkdir -p "$KPATCH_TOOLCHAIN_DIR"
    retry 3 run_quiet curl -LSs --fail --connect-timeout 30 -o /tmp/kpatch-toolchain.tar.xz "$KPATCH_TOOLCHAIN_URL" \
        || error "KPatch-Next: failed to download aarch64-none-elf toolchain!"
    tar -xf /tmp/kpatch-toolchain.tar.xz -C "$KPATCH_TOOLCHAIN_DIR" --strip-components=1 \
        || error "KPatch-Next: failed to extract toolchain!"
    rm -f /tmp/kpatch-toolchain.tar.xz
    mkdir -p "$KPATCH_TOOLCHAIN_CACHE_DIR"
    cp -a "${KPATCH_TOOLCHAIN_DIR}/." "${KPATCH_TOOLCHAIN_CACHE_DIR}/"
    log "KPatch-Next: toolchain downloaded and cached ✅"
fi

[ -x "${KPATCH_TOOLCHAIN_DIR}/bin/aarch64-none-elf-gcc" ] \
    || error "KPatch-Next: aarch64-none-elf-gcc not found after toolchain setup!"

# ---------------------------------------------------------
# Android NDK (required to build kpatch, the userspace binary
# that runs on-device).
#
# Tried relying on the runner's preinstalled NDK first (env vars,
# then scanning ${ANDROID_SDK_ROOT}/ndk, then sdkmanager) — all three
# failed in CI (see docs/CODEX.md / commit history for that attempt).
# Root cause unconfirmed (possibly ANDROID_SDK_ROOT/ANDROID_HOME
# themselves aren't set on this runner, or the image dropped the SDK
# for this runner class). Rather than keep guessing at runner
# internals, download a pinned NDK ourselves — same approach already
# used for the aarch64-none-elf toolchain above, so this addon no
# longer depends on runner-image assumptions at all.
# ---------------------------------------------------------

KPATCH_NDK_VERSION="r27c"
KPATCH_NDK_CACHE_DIR="${HOME}/kpatch-ndk-cache"
KPATCH_NDK_URL="https://dl.google.com/android/repository/android-ndk-${KPATCH_NDK_VERSION}-linux.zip"

if [ -f "${KPATCH_NDK_CACHE_DIR}/build/cmake/android.toolchain.cmake" ]; then
    log "KPatch-Next: restoring Android NDK ${KPATCH_NDK_VERSION} from cache..."
    KPATCH_NDK_DIR="$KPATCH_NDK_CACHE_DIR"
else
    log "KPatch-Next: downloading Android NDK ${KPATCH_NDK_VERSION} (~700MB, one-time this run)..."
    retry 3 run_quiet curl -LSs --fail --connect-timeout 30 -o /tmp/kpatch-ndk.zip "$KPATCH_NDK_URL" \
        || error "KPatch-Next: failed to download Android NDK ${KPATCH_NDK_VERSION}!"
    rm -rf /tmp/kpatch-ndk-extract
    mkdir -p /tmp/kpatch-ndk-extract "$KPATCH_NDK_CACHE_DIR"
    unzip -q /tmp/kpatch-ndk.zip -d /tmp/kpatch-ndk-extract \
        || error "KPatch-Next: failed to extract Android NDK zip!"
    rm -f /tmp/kpatch-ndk.zip
    KPATCH_NDK_EXTRACTED=$(find /tmp/kpatch-ndk-extract -mindepth 1 -maxdepth 1 -type d | head -1)
    [ -n "$KPATCH_NDK_EXTRACTED" ] || error "KPatch-Next: NDK zip extracted but no top-level dir found!"
    mv "${KPATCH_NDK_EXTRACTED}"/* "$KPATCH_NDK_CACHE_DIR"/
    rm -rf /tmp/kpatch-ndk-extract
    log "KPatch-Next: NDK downloaded and cached ✅"
    KPATCH_NDK_DIR="$KPATCH_NDK_CACHE_DIR"
fi

[ -f "${KPATCH_NDK_DIR}/build/cmake/android.toolchain.cmake" ] \
    || error "KPatch-Next: NDK dir at ${KPATCH_NDK_DIR} doesn't contain build/cmake/android.toolchain.cmake — download/extract may be corrupt."

log "KPatch-Next: using NDK at ${KPATCH_NDK_DIR}"

# ---------------------------------------------------------
# Build kpimg (bare-metal ELF, takes over kernel boot to patch it)
# ---------------------------------------------------------

log "🩹 Building kpimg..."
(
    cd "${KPATCH_NEXT_SRC_DIR}/kernel"
    export TARGET_COMPILE="${KPATCH_TOOLCHAIN_DIR}/bin/aarch64-none-elf-"
    export ANDROID=1
    make clean > /dev/null 2>&1 || true
    make
) || error "KPatch-Next: kpimg build failed!"

KPATCH_NEXT_KPIMG="${KPATCH_NEXT_SRC_DIR}/kernel/kpimg"
[ -f "$KPATCH_NEXT_KPIMG" ] || error "KPatch-Next: kpimg build succeeded but output file missing!"

# ---------------------------------------------------------
# Build kptools (host tool — patches the kernel Image post-build,
# doesn't need to run on-device, so plain host GCC is fine)
# ---------------------------------------------------------

log "🩹 Building kptools..."
(
    cd "${KPATCH_NEXT_SRC_DIR}/tools"
    make clean > /dev/null 2>&1 || true
    # tools/Makefile's `clean` target does `rm -rf preset.h`, but preset.h
    # is only ever placed here as a side effect of the kernel/ build
    # (kernel/Makefile: `cp -f include/preset.h ../tools/`). Nothing
    # re-copies it before `make` runs here, so kptools.c fails to find it
    # after a clean. Restore it explicitly before building.
    cp -f "${KPATCH_NEXT_SRC_DIR}/kernel/include/preset.h" .
    make
) || error "KPatch-Next: kptools build failed!"

KPATCH_NEXT_KPTOOLS="${KPATCH_NEXT_SRC_DIR}/tools/kptools"
[ -f "$KPATCH_NEXT_KPTOOLS" ] || error "KPatch-Next: kptools build succeeded but output file missing!"

# ---------------------------------------------------------
# Build kpatch (Android userspace binary, via NDK)
# ---------------------------------------------------------

log "🩹 Building kpatch (Android)..."
(
    cd "${KPATCH_NEXT_SRC_DIR}/user"
    mkdir -p build/android
    cd build/android
    cmake -DCMAKE_TOOLCHAIN_FILE="${KPATCH_NDK_DIR}/build/cmake/android.toolchain.cmake" \
          -DCMAKE_BUILD_TYPE=Release \
          -DANDROID_PLATFORM=android-33 \
          -DANDROID_ABI=arm64-v8a ../.. > /dev/null \
        && cmake --build .
) || error "KPatch-Next: kpatch build failed!"

KPATCH_NEXT_KPATCH_BIN=$(find "${KPATCH_NEXT_SRC_DIR}/user/build/android" -maxdepth 1 -type f -name "kpatch")
[ -n "$KPATCH_NEXT_KPATCH_BIN" ] || error "KPatch-Next: kpatch build succeeded but binary not found!"

export KPATCH_NEXT_KPIMG KPATCH_NEXT_KPTOOLS KPATCH_NEXT_KPATCH_BIN

log "KPatch-Next: kpimg, kptools, kpatch built ✅ (Image patching deferred to post-build stage)"
