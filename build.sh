#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL
# GKI Kernel Build System
# ======================================================

set -eo pipefail

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

KERNEL_VERSION="${KERNEL_VERSION:-6.1}"

case "${KERNEL_VERSION}" in
  "5.10") ANDROID_VERSION="android13" ;;
  "5.15") ANDROID_VERSION="android13" ;;
  "6.1")  ANDROID_VERSION="android14" ;;
  "6.6")  ANDROID_VERSION="android15" ;;
  "6.12") ANDROID_VERSION="android16" ;;
  *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
esac

KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

KERNEL_NAME="Luminaire"
BUILD_USER="chainonyourdoor"
BUILD_HOST="LuminaireCI"

DEFCONFIG="gki_defconfig"
ARCH="arm64"

VARIANT="${VARIANT:-VANILLA}"
PREP_MODE="${PREP_MODE:-false}"
WARMING_MODE="${WARMING_MODE:-false}"
ENABLE_LTO="${ENABLE_LTO:-NONE}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${ROOT_DIR}/workspace"
CLANG_DIR="${ROOT_DIR}/greenforce-clang"
CLANG_BIN="${CLANG_DIR}/bin"
KERNEL_DIR="${WORK_DIR}/kernel"
KERNEL_SRC="${KERNEL_DIR}/common"
AK3_DIR="${WORK_DIR}/AnyKernel3"
OUT_DIR="${WORK_DIR}/out"
PATCH_REPO="${ROOT_DIR}/Luminaire-Patch/${ANDROID_VERSION}-${KERNEL_VERSION}-lts"
COMMON_REPO="${ROOT_DIR}/Luminaire-Patch/common"

CCACHE_BIN="${ROOT_DIR}/ccache-bin/ccache"
CCACHE_WRAPPER_DIR="${ROOT_DIR}/ccache-wrappers"
export CCACHE_DIR="${CCACHE_DIR:-${ROOT_DIR}/.ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1

export GIT_CLONE_PROTECTION_ACTIVE=false
export KBUILD_BUILD_USER="$BUILD_USER"
export KBUILD_BUILD_HOST="$BUILD_HOST"
export KCFLAGS="-w"

MAKE_ARGS=(
    -C "$KERNEL_SRC"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    LLVM=1
    LLVM_IAS=1
    BRANCH="${KERNEL_BRANCH}"
    KMI_GENERATION="${KMI_GENERATION}"
    LOCALVERSION="-${KERNEL_NAME}"
    -j"$(nproc --all)"
)

DATE=$(date +"%b%d")
ZIP_NAME="LuminaireAnykernel3-${DATE}R${GITHUB_RUN_NUMBER:-0}.zip"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo ""
    log "========================================"
    log "  ✨ Luminaire Protocol — ${VARIANT}"
    log "  🖥️ CPU: $(nproc --all) cores"
    log "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    log "  📅 $(date)"
    log "========================================"
    echo ""

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    clone_patch_repo
    run_setup
    download_kernel_source

    if [ "$PREP_MODE" = "true" ]; then
        log "✅ Prep Complete!"
        exit 0
    fi

    run_fixes
    run_patches
    build_kernel

    if [ "$WARMING_MODE" = "true" ]; then
        log "🔥 Warming Complete — skipping packaging"
        exit 0
    fi

    package_anykernel3

    echo ""
    log "========================================"
    log "  ✅ Build Complete! — ${ZIP_NAME}"
    log "========================================"
    echo ""
}

# ======================================================
# 🔑 CLONE PATCH REPO
# ======================================================

clone_patch_repo() {
    echo "::group::🔑 Luminaire-Patch"
    log "Cloning Luminaire-Patch..."
    git clone --depth=1 \
        https://x-access-token:${PERSONAL_TOKEN}@github.com/chainonyourdoor/Luminaire-Patch.git \
        "${ROOT_DIR}/Luminaire-Patch"
    echo "::endgroup::"
}

# ======================================================
# 📦 SETUP
# ======================================================

run_setup() {
    echo "::group::📦 Setup"
    for script in "${COMMON_REPO}/setup/"*.sh; do
        log "Running: $(basename "$script")..."
        source "$script" || error "Setup failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# 📥 KERNEL SOURCE
# ======================================================

download_kernel_source() {
    echo "::group::📥 Kernel Source"
    if [ "${USE_KERNEL_CACHE:-false}" = "true" ] && [ -d "${HOME}/kernel-cache/common" ]; then
        log "Restoring from cache..."
        cp -a "${HOME}/kernel-cache/." "${KERNEL_DIR}/"
        log "Kernel source restored ✅"
    else
        log "Cloning kernel source..."
        git clone -q --depth=1 \
            -b "$KERNEL_BRANCH" \
            https://github.com/chainonyourdoor/android_kernel_common-${KERNEL_VERSION} \
            "${KERNEL_DIR}/common" || error "Failed to clone kernel!"
        log "Saving to cache..."
        mkdir -p "${HOME}/kernel-cache"
        rsync -a "${KERNEL_DIR}/" "${HOME}/kernel-cache/"
    fi
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')"
    KMI_GENERATION="$(grep '^KMI_GENERATION=' "${KERNEL_SRC}/build.config.common" "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)"
    [ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found in kernel source!"
    log "Kernel source ready ✅ (sublevel: ${SUBLEVEL}, KMI: ${KMI_GENERATION})"
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 🔧 FIXES
# ======================================================

run_fixes() {
    echo "::group::🔧 Fixes"
    for fix in "${COMMON_REPO}/fixes/"*.sh; do
        log "Applying: $(basename "$fix")..."
        source "$fix" || error "Fix failed: $(basename "$fix")"
    done
    for patch in "${PATCH_REPO}/patches/"*.patch; do
        [ -f "$patch" ] || continue
        log "Applying patch: $(basename "$patch")..."
        if patch -p1 --dry-run --forward -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
            patch -p1 -d "$KERNEL_SRC" < "$patch" || error "Patch failed: $(basename "$patch")"
            log "$(basename "$patch") applied ✅"
        elif patch -p1 --dry-run --reverse -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
            log "$(basename "$patch") already applied, skipping."
        else
            error "$(basename "$patch") failed — conflict!"
        fi
    done
    log "All fixes applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🩹 PATCHES
# ======================================================

run_patches() {
    echo "::group::🩹 Patches"
    export KBUILD_BUILD_TIMESTAMP="$(git -C "$KERNEL_SRC" log -1 --format=%cd --date=format:'%a %b %d %T %Z %Y' 2>/dev/null || date)"

    touch "${KERNEL_SRC}/.scmversion"

    log "Generating defconfig..."
    make "${MAKE_ARGS[@]}" "$DEFCONFIG" || error "Defconfig failed!"

    log "Applying Luminaire configs..."
    source "${COMMON_REPO}/luminaire_defconfig.sh"

    log "Syncing config..."
    make "${MAKE_ARGS[@]}" olddefconfig || error "olddefconfig failed!"

    log "Patches applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🏗️ BUILD KERNEL
# ======================================================

build_kernel() {
    echo "::group::🏗️ Build Kernel"
    log "Building kernel..."
    START_TIME=$(date +%s)

    (
        set +eo pipefail
        while true; do
            sleep 30
            ELAPSED=$(( $(date +%s) - START_TIME ))
            printf "[LOG] Still building... ⏱️ %02d:%02d:%02d elapsed\n" \
                $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60))
        done
    ) &
    HEARTBEAT_PID=$!

    make "${MAKE_ARGS[@]}" \
        || { kill "$HEARTBEAT_PID" 2>/dev/null; error "Build failed!"; }

    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true

    BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
    log "Build completed in ${BUILD_SECONDS}s ✅"
    echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"

    echo "::group::📊 Ccache Stats"
    [ -f "$CCACHE_BIN" ] && $CCACHE_BIN --show-stats 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 📦 PACKAGE ANYKERNEL3
# ======================================================

package_anykernel3() {
    echo "::group::📦 Package AnyKernel3"
    if [ "${USE_AK3_CACHE:-false}" = "true" ] && [ -d "${HOME}/ak3-cache" ]; then
        cp -a "${HOME}/ak3-cache/." "${AK3_DIR}/"
        log "AnyKernel3 restored from cache ✅"
    else
        git clone -q --depth=1 \
            https://github.com/chainonyourdoor/AnyKernel3-Luminaire.git "$AK3_DIR" \
            || error "Failed to clone AK3!"
        mkdir -p "${HOME}/ak3-cache"
        cp -a "${AK3_DIR}/." "${HOME}/ak3-cache/"
    fi

    KERNEL_IMG=""
    for img in Image Image.gz Image.gz-dtb Image-dtb; do
        BOOT_PATH="${OUT_DIR}/arch/${ARCH}/boot/${img}"
        if [ -f "$BOOT_PATH" ]; then
            KERNEL_IMG="$BOOT_PATH"
            log "Kernel image: $img"
            break
        fi
    done
    [ -z "$KERNEL_IMG" ] && error "Kernel image not found!"

    cp "$KERNEL_IMG" "${AK3_DIR}/"

    ZIP_PATH="/tmp/${ZIP_NAME}"
    export ZIP_PATH
    export ZIP_NAME
    cd "$AK3_DIR"
    zip -r9 "$ZIP_PATH" . -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE"
    cd "$ROOT_DIR"

    log "ZIP ready: ${ZIP_NAME} ✅"
    echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "ZIP_PATH=${ZIP_PATH}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 🧹 CLEANUP
# ======================================================

cleanup() {
    true
}
trap cleanup EXIT

main "$@"
