#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL
# GKI Kernel Build System — android14-6.1
# ======================================================

set -eo pipefail

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

ANDROID_VERSION="android14"
KERNEL_VERSION="6.1"
KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"
KMI_GENERATION="11"

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

CCACHE_BIN="${ROOT_DIR}/ccache-bin/ccache"
CCACHE_WRAPPER_DIR="${ROOT_DIR}/ccache-wrappers"
export CCACHE_DIR="${CCACHE_DIR:-${ROOT_DIR}/.ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1

export GIT_CLONE_PROTECTION_ACTIVE=false
export KBUILD_BUILD_USER="$BUILD_USER"
export KBUILD_BUILD_HOST="$BUILD_HOST"
export KBUILD_BUILD_VERSION=1
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

LOG_FILE="/tmp/luminaire-$(date +%s).log"
touch "$LOG_FILE"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    exec 1> >(tee -a "$LOG_FILE") 2>&1

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
    send_telegram

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
    for script in "${PATCH_REPO}/setup/"*.sh; do
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
            https://github.com/chainonyourdoor/android_kernel_common-6.1 \
            "${KERNEL_DIR}/common" || error "Failed to clone kernel!"
        log "Saving to cache..."
        mkdir -p "${HOME}/kernel-cache"
        rsync -a "${KERNEL_DIR}/" "${HOME}/kernel-cache/"
    fi
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')"
    log "Kernel source ready ✅ (sublevel: ${SUBLEVEL})"
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 🔧 FIXES
# ======================================================

run_fixes() {
    echo "::group::🔧 Fixes"
    for fix in "${PATCH_REPO}/fixes/"*.sh; do
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
    source "${PATCH_REPO}/luminaire_defconfig.sh"

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
    cd "$AK3_DIR"
    zip -r9 "$ZIP_PATH" . -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE"
    cd "$ROOT_DIR"

    log "ZIP ready: ${ZIP_NAME} ✅"
    echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "ZIP_PATH=${ZIP_PATH}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 📲 TELEGRAM
# ======================================================

send_telegram() {
    echo "::group::📲 Telegram"
    LINUX_VERSION=$(make -C "$KERNEL_SRC" kernelversion 2>/dev/null | \
        grep -v "make" | head -n 1 | tr -d '[:space:]' || true)

    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${ZIP_PATH:-}" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_BUILD:+-F "message_thread_id=${TELEGRAM_THREAD_ID_BUILD}"} \
            -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
            -F "caption=<b>Luminaire ${VARIANT}</b>
Linux     : ${LINUX_VERSION:-N/A}
Compiler  : ${COMPILER_STRING:-N/A}
Date      : $(date +'%d %b %Y')" \
            -F "parse_mode=HTML" || true
    fi
    echo "::endgroup::"
}

# ======================================================
# 🧹 CLEANUP
# ======================================================

cleanup() {
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        CAPTION="📄 Build Log"
        [ -n "${BUILD_SECONDS:-}" ] && \
            CAPTION="✅ ${BUILD_SECONDS}s | 📦 ${ZIP_NAME:-unknown}"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_LOG:+-F "message_thread_id=${TELEGRAM_THREAD_ID_LOG}"} \
            -F "document=@${LOG_FILE};filename=build-$(date +%Y%m%d-%H%M).log" \
            -F "caption=${CAPTION}" || true
    fi
}
trap cleanup EXIT

main "$@"
