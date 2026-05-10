#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL
# ======================================================

set -euo pipefail

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

ANDROID_VERSION="android14"
KERNEL_VERSION="6.1"
OS_PATCH_LEVEL="2024-01"
FORMATTED_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-${OS_PATCH_LEVEL}"

ARCH="arm64"
BUILD_USER="chainonyourdoor"
BUILD_HOST="LuminaireCI"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="${ROOT_DIR}/kernel"
AK3_DIR="${ROOT_DIR}/AnyKernel3"
KERNEL_PATCHES_DIR="${ROOT_DIR}/kernel_patches"
FRAGMENT="${ROOT_DIR}/luminaire.fragment"
LOG_FILE="/tmp/luminaire-$(date +%s).log"
touch "$LOG_FILE"

# ======================================================
# 📦 IMPORT FUNCTIONS
# ======================================================
source "${ROOT_DIR}/functions.sh"

# ======================================================
# 🚀 MAIN
# ======================================================
main() {
    exec 1> >(tee -a "$LOG_FILE") 2>&1

    echo ""
    log "========================================"
    log "  ✨ Luminaire Protocol Build Start"
    log "  🖥️ CPU: $(nproc --all) cores"
    log "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    log "  📅 $(date)"
    log "========================================"
    echo ""

    # ======================================================
    # 📦 SETUP BUILD ENVIRONMENT
    # ======================================================
    echo "::group::📦 Setup Build Environment"

    mkdir -p "$KERNEL_DIR"

    log "Cloning kernel_patches..."
    git clone --depth=1 https://github.com/WildKernels/kernel_patches.git \
        "${ROOT_DIR}/kernel_patches_wild"

    log "Cloning AnyKernel3..."
    git clone --depth=1 -b gki-2.0 \
        https://github.com/WildKernels/AnyKernel3.git "$AK3_DIR"

    log "Cloning AOSP build-tools..."
    git clone https://android.googlesource.com/kernel/prebuilts/build-tools \
        -b main-kernel-2025 --depth=1 "${ROOT_DIR}/kernel-build-tools"

    log "Cloning mkbootimg..."
    git clone https://android.googlesource.com/platform/system/tools/mkbootimg \
        -b main-kernel-2025 --depth=1 "${ROOT_DIR}/mkbootimg"

    export AVBTOOL="${ROOT_DIR}/kernel-build-tools/linux-x86/bin/avbtool"
    export MKBOOTIMG="${ROOT_DIR}/mkbootimg/mkbootimg.py"
    export UNPACK_BOOTIMG="${ROOT_DIR}/mkbootimg/unpack_bootimg.py"
    export BOOT_SIGN_KEY_PATH="${ROOT_DIR}/kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem"

    echo "::endgroup::"

    # ======================================================
    # 📥 DOWNLOAD KERNEL SOURCE
    # ======================================================
    echo "::group::📥 Kernel Source"
    log "Fetching manifest for ${FORMATTED_BRANCH}..."

    cd "$KERNEL_DIR"

    MAIN_MANIFEST_URL="https://android.googlesource.com/kernel/manifest/+/refs/heads/common-${FORMATTED_BRANCH}/default.xml?format=TEXT"
    DEPRECATED_MANIFEST_URL="https://android.googlesource.com/kernel/manifest/+/refs/heads/deprecated/common-${FORMATTED_BRANCH}/default.xml?format=TEXT"

    if curl -fsSL "$MAIN_MANIFEST_URL" | base64 -d > manifest.xml; then
        log "Manifest fetched from main branch."
    else
        log "Main branch not found, trying deprecated..."
        curl -fsSL "$DEPRECATED_MANIFEST_URL" | base64 -d > manifest.xml \
            || error "Failed to fetch manifest!"
    fi

    log "Downloading kernel source (parallel)..."
    sudo apt-get install -y --no-install-recommends aria2 pigz python3 > /dev/null 2>&1
    python3 "${ROOT_DIR}/fast_parallel_download.py" \
        || error "Kernel source download failed!"

    log "Kernel source ready ✅"
    echo "::endgroup::"

    # ======================================================
    # 🔧 KERNEL FIXES (GLIBC >= 2.38)
    # ======================================================
    echo "::group::🔧 Kernel Fixes"
    cd "${KERNEL_DIR}/common"

    GLIBC_VERSION="$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
    log "GLIBC version: ${GLIBC_VERSION}"

    if [ "$(printf '%s\n' "2.38" "$GLIBC_VERSION" | sort -V | head -n 1)" = "2.38" ]; then
        log "GLIBC >= 2.38, applying Makefile fix..."
        if grep -q '$(Q)$(MAKE) -C $(SUBCMD_SRC) OUTPUT=$(abspath $(dir $@))/ $(abspath $@)' \
                tools/bpf/resolve_btfids/Makefile; then
            sed -i 's/$(Q)$(MAKE) -C $(SUBCMD_SRC) OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/$(Q)$(MAKE) -C $(SUBCMD_SRC) EXTRA_CFLAGS="$(CFLAGS)" OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/' \
                tools/bpf/resolve_btfids/Makefile
            log "Makefile fix applied ✅"
        else
            log "Makefile fix not needed."
        fi
    fi

    echo "::endgroup::"

    # ======================================================
    # 🧹 CLEAN DIRTY FLAGS
    # ======================================================
    echo "::group::🧹 Clean Dirty Flags"
    cd "${KERNEL_DIR}/common"

    sed -i 's/-dirty//' scripts/setlocalversion

    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    git add .
    git commit -m "Luminaire: Clean Dirty Flag" || true

    echo "::endgroup::"

    # ======================================================
    # 📝 BUILD FRAGMENT
    # ======================================================
    echo "::group::📝 Build Fragment"

    cat > "$FRAGMENT" << 'FRAGMENT_EOF'
# Mountify Support
CONFIG_OVERLAY_FS=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y

# KPatch-Next Support
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# TCP Congestion Control
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_TCP_CONG_CUBIC=y
CONFIG_TCP_CONG_BIC=y
CONFIG_TCP_CONG_WESTWOOD=y
CONFIG_TCP_CONG_HTCP=y
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"
CONFIG_NET_SCH_FQ=y
CONFIG_NET_SCH_FQ_CODEL=y

# IP SET & IPv6 NAT
CONFIG_IP_SET=y
CONFIG_IP_SET_MAX=65534
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
FRAGMENT_EOF

    log "Fragment ready ✅"
    echo "::endgroup::"

    # ======================================================
    # 🏗️ BUILD KERNEL
    # ======================================================
    echo "::group::🏗️ Build Kernel"
    cd "$KERNEL_DIR"

    export KBUILD_BUILD_USER="$BUILD_USER"
    export KBUILD_BUILD_HOST="$BUILD_HOST"

    log "Building kernel using AOSP build system..."
    START_TIME=$(date +%s)

    (
        set +eo pipefail
        while true; do
            sleep 30
            ELAPSED=$(( $(date +%s) - START_TIME ))
            ELAPSED_FMT=$(printf "%02d:%02d:%02d" \
                $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))
            echo "[LOG] Still building... ⏱️ ${ELAPSED_FMT} elapsed"
        done
    ) &
    HEARTBEAT_PID=$!

    SKIP_VENDOR_BOOT=1 \
    SKIP_EXT_MODULES=1 \
    SKIP_CP_KERNEL_HDR=1 \
    SKIP_MRPROPER=1 \
    LTO=thin \
    GKI_DEFCONFIG_FRAGMENT="$FRAGMENT" \
    BUILD_CONFIG=common/build.config.gki.aarch64 \
    build/build.sh -j"$(nproc)" \
        || { kill "$HEARTBEAT_PID" 2>/dev/null; error "Build failed!"; }

    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true

    END_TIME=$(date +%s)
    BUILD_SECONDS=$(( END_TIME - START_TIME ))
    log "Build completed in ${BUILD_SECONDS}s ✅"
    echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    echo "::endgroup::"

    # ======================================================
    # 📦 PACKAGE ANYKERNEL3
    # ======================================================
    echo "::group::📦 Package AnyKernel3"

    IMAGE_PATH="${KERNEL_DIR}/out/${ANDROID_VERSION}-${KERNEL_VERSION}/dist/Image"
    [ -f "$IMAGE_PATH" ] || error "Kernel Image not found at: ${IMAGE_PATH}"

    cp "$IMAGE_PATH" "${AK3_DIR}/Image"

    DATE=$(date +"%b%d")
    ZIP_NAME="LuminaireProtocol-Vanilla-${DATE}R${GITHUB_RUN_NUMBER:-0}.zip"
    ZIP_PATH="/tmp/${ZIP_NAME}"

    cd "$AK3_DIR"
    zip -r9 "$ZIP_PATH" . \
        -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE"
    cd "$ROOT_DIR"

    log "ZIP ready: ${ZIP_NAME} ✅"
    echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "ZIP_PATH=${ZIP_PATH}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    echo "::endgroup::"

    # ======================================================
    # 📲 SEND TO TELEGRAM
    # ======================================================
    echo "::group::📲 Telegram"
    LINUX_VERSION=$(cat "${KERNEL_DIR}/common/Makefile" 2>/dev/null | \
        grep -E "^VERSION|^PATCHLEVEL|^SUBLEVEL" | \
        awk '{print $3}' | tr '\n' '.' | sed 's/\.$//')

    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "$ZIP_PATH" ]; then
        log "Sending ZIP to Telegram..."
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_BUILD:+-F "message_thread_id=${TELEGRAM_THREAD_ID_BUILD}"} \
            -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
            -F "caption=✨ <b>Luminaire Protocol</b>

Linux : ${LINUX_VERSION:-N/A}
Date : $(date +"%d %b %Y")" \
            -F "parse_mode=HTML" || true
        log "ZIP sent ✅"
    fi
    echo "::endgroup::"

    echo ""
    log "========================================"
    log "  ✅ Build Complete!"
    log "  📦 ${ZIP_NAME}"
    log "========================================"
    echo ""
}

cleanup() {
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        local CAPTION="📄 Full Build Log"
        [ -n "${BUILD_SECONDS:-}" ] && \
            CAPTION="✅ Build Complete! ⏱️ ${BUILD_SECONDS}s | 📦 ${ZIP_NAME:-unknown}"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_LOG:+-F "message_thread_id=${TELEGRAM_THREAD_ID_LOG}"} \
            -F "document=@${LOG_FILE};filename=build-$(date +%Y%m%d-%H%M).log" \
            -F "caption=${CAPTION}" || true
    fi
}
trap cleanup EXIT

main "$@"
