#!/usr/bin/env bash

# ======================================================
# 🩹 ADDON — KPatch-Next
# Kernel patch/hook framework (KPM module support)
# Repo: https://github.com/KernelSU-Next/KPatch-Next
# ======================================================

KPATCH_NEXT_REPO="https://github.com/KernelSU-Next/KPatch-Next.git"
KPATCH_NEXT_SRC_DIR="${WORKSPACE_DIR}/kpatch-next"

log "🩹 Fetching KPatch-Next source..."

if [ -d "${KPATCH_NEXT_SRC_DIR}/.git" ]; then
    log "KPatch-Next: source already present, skipping clone."
else
    rm -rf "${KPATCH_NEXT_SRC_DIR}"
    retry 3 run_quiet git clone -q --depth=1 "${KPATCH_NEXT_REPO}" "${KPATCH_NEXT_SRC_DIR}" \
        || error "KPatch-Next: failed to clone source!"
fi

[ -d "${KPATCH_NEXT_SRC_DIR}/kernel" ] && [ -d "${KPATCH_NEXT_SRC_DIR}/tools" ] && [ -d "${KPATCH_NEXT_SRC_DIR}/user" ] \
    || error "KPatch-Next: cloned repo missing kernel/tools/user — layout may have changed upstream!"

# ---------------------------------------------------------
# Bare-metal aarch64-none-elf toolchain (required for kpimg —
# aarch64-linux-gnu- from TOOL_CROSS_COMPILE will NOT work here,
# kpimg is a freestanding ELF, not a userspace/kernel-module binary)
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
# that runs on-device). GitHub-hosted ubuntu-latest runners DO
# ship a preinstalled NDK, but ANDROID_NDK_LATEST_HOME/ANDROID_NDK_HOME/
# ANDROID_NDK_ROOT are only written to /etc/environment by the runner
# image's installer script, which job steps don't inherit — so those
# vars are usually empty here even though the NDK is on disk. Fall
# back to scanning where it actually lives, then to installing one
# via sdkmanager (already licensed on the image) as a last resort.
# ---------------------------------------------------------

KPATCH_NDK_DIR=""
for _ndk_var in ANDROID_NDK_LATEST_HOME ANDROID_NDK_HOME ANDROID_NDK_ROOT ANDROID_NDK; do
    _ndk_val="${!_ndk_var:-}"
    if [ -n "$_ndk_val" ] && [ -d "$_ndk_val" ]; then
        KPATCH_NDK_DIR="$_ndk_val"
        log "KPatch-Next: found NDK via \$${_ndk_var}"
        break
    fi
done

if [ -z "$KPATCH_NDK_DIR" ]; then
    for _sdk_base in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "/usr/local/lib/android/sdk"; do
        [ -n "$_sdk_base" ] && [ -d "${_sdk_base}/ndk" ] || continue
        KPATCH_NDK_DIR=$(find "${_sdk_base}/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
        [ -n "$KPATCH_NDK_DIR" ] && { log "KPatch-Next: found NDK under ${_sdk_base}/ndk"; break; }
    done
fi

if [ -z "$KPATCH_NDK_DIR" ]; then
    KPATCH_SDKMANAGER=$(command -v sdkmanager 2>/dev/null || true)
    [ -z "$KPATCH_SDKMANAGER" ] && KPATCH_SDKMANAGER=$(find "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}" -type f -name "sdkmanager" 2>/dev/null | head -1)
    if [ -n "$KPATCH_SDKMANAGER" ]; then
        warn "KPatch-Next: no preinstalled NDK found — installing ndk;27.3.13750724 via sdkmanager (one-time, will slow this run down)..."
        KPATCH_SDK_BASE="${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"
        yes | "$KPATCH_SDKMANAGER" --sdk_root="$KPATCH_SDK_BASE" "ndk;27.3.13750724" > /dev/null 2>&1
        [ -d "${KPATCH_SDK_BASE}/ndk/27.3.13750724" ] && KPATCH_NDK_DIR="${KPATCH_SDK_BASE}/ndk/27.3.13750724"
    fi
fi

[ -n "$KPATCH_NDK_DIR" ] && [ -d "$KPATCH_NDK_DIR" ] \
    || error "KPatch-Next: Android NDK not found — checked ANDROID_NDK_LATEST_HOME/ANDROID_NDK_HOME/ANDROID_NDK_ROOT/ANDROID_NDK, scanned \${ANDROID_SDK_ROOT}/ndk and \${ANDROID_HOME}/ndk, and the sdkmanager install fallback also failed. Runner image may have changed layout."

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
