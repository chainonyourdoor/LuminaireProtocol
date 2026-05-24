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

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

case "${KERNEL_VERSION}" in
  "5.10") ANDROID_VERSION="android13" ;;
  "5.15") ANDROID_VERSION="android13" ;;
  "6.1")  ANDROID_VERSION="android14" ;;
  "6.6")  ANDROID_VERSION="android15" ;;
  "6.12") ANDROID_VERSION="android16" ;;
  *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
esac

KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"
KLEAF_MANIFEST_BRANCH="common-${ANDROID_VERSION}-${KERNEL_VERSION}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LUMINAIRE_PATCH_DIR="${ROOT_DIR}/Luminaire-Patch/common"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo "========================================"
    echo "  ✨ Luminaire Protocol — ${VARIANT}"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "  📅 $(date)"
    echo "========================================"

    clone_patch_repo
    run_setup

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    download_kernel_source

    if [ "$PREPARE_ARSENAL" = "true" ]; then
        log "✅ Prep Complete!"
        exit 0
    fi

    run_branding
    run_fixes

    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        build_kernel_kleaf
    else
        setup_make_args
        run_patches
        build_kernel
    fi

    if [ "$WARMING_MODE" = "true" ]; then
        log "🔥 Warming Complete — skipping packaging"
        exit 0
    fi

    run_release

    echo "========================================"
    echo "  Build Complete! — LuminaireAk3-${KERNEL_VERSION}.${SUBLEVEL}-R${GITHUB_RUN_NUMBER:-0}.zip"
    echo "========================================"
}

# ======================================================
# 🌀 CLONE PATCH REPO
# ======================================================

clone_patch_repo() {
    echo "::group::🌀 Luminaire-Patch"
    if [ -d "${ROOT_DIR}/Luminaire-Patch/.git" ]; then
        log "Luminaire-Patch already exists, skipping clone."
    else
        log "Cloning Luminaire-Patch..."
        git clone --depth=1 \
            https://x-access-token:${PERSONAL_TOKEN}@github.com/chainonyourdoor/Luminaire-Patch.git \
            "${ROOT_DIR}/Luminaire-Patch"
    fi
    echo "::endgroup::"
}

# ======================================================
# 📦 SETUP
# ======================================================

run_setup() {
    echo "::group::📦 Setup"
    for script in "${LUMINAIRE_PATCH_DIR}/setup/"*.sh; do
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

    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        _download_kleaf
    else
        _download_make
    fi

    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')"
    KMI_GENERATION="$(grep '^KMI_GENERATION=' "${KERNEL_SRC}/build.config.common" "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)"
    [ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found in kernel source!"
    export SUBLEVEL KMI_GENERATION
    log "Kernel source ready ✅ (sublevel: ${SUBLEVEL}, KMI: ${KMI_GENERATION})"
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

_download_make() {
    if [ "${USE_KERNEL_CACHE}" = "true" ] && [ -d "${HOME}/kernel-cache/common" ]; then
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
}

_download_kleaf() {
    if [ "${USE_KERNEL_CACHE}" = "true" ] && [ -d "${HOME}/kernel-cache/common" ]; then
        log "Restoring from cache..."
        cp -a "${HOME}/kernel-cache/." "${KERNEL_DIR}/"
        log "Kernel source restored ✅"
    else
        log "Syncing kernel workspace via repo (Kleaf)..."
        command -v repo &>/dev/null || \
            curl -s https://storage.googleapis.com/git-repo-downloads/repo \
                -o /usr/local/bin/repo && chmod +x /usr/local/bin/repo
        mkdir -p "$KERNEL_DIR" && cd "$KERNEL_DIR"
        repo init -u https://android.googlesource.com/kernel/manifest \
            -b "${KLEAF_MANIFEST_BRANCH}" --depth=1 -q || error "repo init failed!"
        repo sync -c -j"$(nproc --all)" --no-tags --no-clone-bundle -q \
            || error "repo sync failed!"
        cd "$ROOT_DIR"
        log "Saving to cache..."
        mkdir -p "${HOME}/kernel-cache"
        rsync -a "${KERNEL_DIR}/" "${HOME}/kernel-cache/"
    fi
}

# ======================================================
# 🏷️ BRANDING
# ======================================================

run_branding() {
    echo "::group::🏷️ Branding"
    source "${LUMINAIRE_PATCH_DIR}/branding/branding.sh" || error "Branding failed!"
    log "Branding applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🛠️ MAKE ARGS
# ======================================================

setup_make_args() {
    MAKE_ARGS=(
        -C "$KERNEL_SRC"
        O="$OUT_DIR"
        ARCH="$ARCH"
        CROSS_COMPILE="$TOOL_CROSS_COMPILE"
        CROSS_COMPILE_COMPAT="$TOOL_CROSS_COMPILE_COMPAT"
        LLVM=1
        LLVM_IAS=1
        BRANCH="${KERNEL_BRANCH}"
        KMI_GENERATION="${KMI_GENERATION}"
        LOCALVERSION="-${ANDROID_VERSION}-${KMI_GENERATION}-${KERNEL_NAME}"
        KBUILD_BUILD_USER="${BUILD_USER}"
        KBUILD_BUILD_HOST="${BUILD_HOST}"
        -j"$(nproc --all)"
    )
}

# ======================================================
# 🔧 FIXES
# ======================================================

run_fixes() {
    echo "::group::🔧 Fixes"
    for fix in "${LUMINAIRE_PATCH_DIR}/fixes/"*.sh; do
        log "Applying: $(basename "$fix")..."
        source "$fix" || error "Fix failed: $(basename "$fix")"
    done
    log "All fixes applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🩹 PATCHES
# ======================================================

run_patches() {
    echo "::group::🩹 Patches"
    touch "${KERNEL_SRC}/.scmversion"

    log "Generating defconfig..."
    make "${MAKE_ARGS[@]}" "$DEFCONFIG" || error "Defconfig failed!"

    log "Applying Luminaire configs..."
    source "${LUMINAIRE_PATCH_DIR}/luminaire_defconfig.sh"

    log "Syncing config..."
    make "${MAKE_ARGS[@]}" olddefconfig || error "olddefconfig failed!"

    log "Applying version patches..."
    for patch in "${VERSION_PATCH_DIR}/patches/"*.patch; do
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

    log "Patches applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🏗️ BUILD KERNEL — KLEAF
# ======================================================

build_kernel_kleaf() {
    echo "::group::🏗️ Build Kernel (Kleaf)"
    log "Building kernel with Kleaf (Bazel)..."
    START_TIME=$(date +%s)

    KLEAF_ARGS=(
        --config=fast
        --lto="${ENABLE_LTO,,}"
        --action_env=KBUILD_BUILD_USER="${BUILD_USER}"
        --action_env=KBUILD_BUILD_HOST="${BUILD_HOST}"
    )

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

    cd "$KERNEL_DIR"
    tools/bazel build "${KLEAF_ARGS[@]}" //common:kernel_aarch64 \
        || { kill "$HEARTBEAT_PID" 2>/dev/null; error "Kleaf build failed!"; }
    cd "$ROOT_DIR"

    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true

    BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
    log "Kleaf build completed in ${BUILD_SECONDS}s ✅"
    echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 🏗️ BUILD KERNEL — MAKE
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
}

# ======================================================
# 🚀 RELEASE
# ======================================================

run_release() {
    echo "::group::🚀 Release"
    for script in "${LUMINAIRE_PATCH_DIR}/release/"*.sh; do
        log "Running: $(basename "$script")..."
        source "$script" || error "Release failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

main "$@"
