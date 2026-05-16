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
FORMATTED_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

BUILD_USER="chainonyourdoor"
BUILD_HOST="LuminaireCI"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="${ROOT_DIR}/kernel"
AK3_DIR="${ROOT_DIR}/AnyKernel3"
FRAGMENT="${ROOT_DIR}/luminaire.fragment"
LOG_FILE="/tmp/luminaire-$(date +%s).log"
touch "$LOG_FILE"

BAZEL_CACHE_DIR="${HOME}/.cache/bazel"
LD_CACHE_DIR="${HOME}/.ld_cache"

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
        "${ROOT_DIR}/kernel_patches"

    log "Cloning AnyKernel3..."
    git clone --depth=1 -b gki-2.0 \
        https://github.com/chainonyourdoor/AnyKernel3-Luminaire.git "$AK3_DIR"

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

    if curl -fsSL "$MAIN_MANIFEST_URL" | base64 -d > manifest.xml; then
        log "Manifest fetched from common-${FORMATTED_BRANCH}."
    else
        error "Failed to fetch manifest for ${FORMATTED_BRANCH}!"
    fi

    log "Downloading kernel source (parallel)..."
    sudo apt-get install -y --no-install-recommends aria2 pigz python3 > /dev/null 2>&1
    python3 "${ROOT_DIR}/fast_parallel_download.py" \
        || error "Kernel source download failed!"

    log "Kernel source ready ✅"
    echo "::endgroup::"

    # ======================================================
    # 📋 EXTRACT SUBLEVEL
    # ======================================================
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_DIR}/common/Makefile" | awk '{print $3}')"
    log "Kernel sublevel: ${SUBLEVEL}"
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

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

    # Legacy build system dirty flag
    sed -i 's/-dirty//' scripts/setlocalversion

    # Kleaf/Bazel dirty flag
    if [ -f "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl" ]; then
        sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" \
            "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
        log "stamp.bzl dirty flag cleaned ✅"
    fi

    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    git add .
    git commit -m "Luminaire: Clean Dirty Flag" || true
    echo "::endgroup::"

    # ======================================================
    # 🔩 DROIDSPACES KABI PATCHES
    # ======================================================
    echo "::group::🔩 Droidspaces KABI Patches"
    cd "${KERNEL_DIR}/common"

    # For android14-6.1: apply sysvipc KABI fix
    SYSVIPC_PATCH="${ROOT_DIR}/kernel_patches/common/droidspaces/fix_sysvipc_kabi_6_7_8.patch"
    if [ -f "$SYSVIPC_PATCH" ]; then
        log "Applying sysvipc KABI fix..."
        patch -p1 < "$SYSVIPC_PATCH" \
            && log "sysvipc KABI fix applied ✅" \
            || log "sysvipc KABI fix skipped (already applied?)"
    fi

    echo "::endgroup::"

    # ======================================================
    # 🔐 SETUP KERNELSU-NEXT
    # ======================================================
    echo "::group::🔐 KernelSU-Next"
    cd "${KERNEL_DIR}"

    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" \
        | bash -s 293ca016cf7196c2e96403a929ea3f464fd3568b \
        || error "Failed to setup KernelSU-Next!"

    cd "${KERNEL_DIR}/KernelSU-Next/kernel"
    COMMITS_COUNT=$(git rev-list --count HEAD)
    KSU_VERSION=$((COMMITS_COUNT + 30000))
    sed -i "s/^KSU_VERSION_FALLBACK := 1$/KSU_VERSION_FALLBACK := ${KSU_VERSION}/" Kbuild

    KSU_GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.0.1')"
    sed -i "s/^KSU_VERSION_TAG_FALLBACK := v0.0.1$/KSU_VERSION_TAG_FALLBACK := ${KSU_GIT_TAG}/" Kbuild


    log "KernelSU-Next setup ✅ (version: ${KSU_VERSION}, tag: ${KSU_GIT_TAG})"
    echo "KSU_VERSION=${KSU_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "KSU_GIT_TAG=${KSU_GIT_TAG}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"

    # ======================================================
    # 🛡️ SETUP SUSFS
    # ======================================================
    echo "::group::🛡️ SUSFS"
    cd "${ROOT_DIR}"

    SUSFS_BRANCH="gki-${ANDROID_VERSION}-${KERNEL_VERSION}"
    SUSFS_COMMIT="ef16cbce5c5195988b9b630de85466148cbbcdef"

    log "Cloning SUSFS branch: ${SUSFS_BRANCH}..."
    git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH" susfs4ksu \
        || error "Failed to clone SUSFS!"
    cd susfs4ksu && git checkout "$SUSFS_COMMIT" && cd "${ROOT_DIR}"

    cd "${KERNEL_DIR}/common"

    # Apply fake patches for android14-6.1 (required for SUSFS patch to apply cleanly)
    log "Applying fake patches for android14-6.1 (sublevel: ${SUBLEVEL})..."
    if [ "${SUBLEVEL}" -le 25 ]; then
        sed -i '/^#include <trace\/events\/oom.h>$/a #include <trace/hooks/sched.h>' fs/proc/base.c
    fi
    if [ "${SUBLEVEL}" -le 141 ]; then
        sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux\/dma-buf.h>' fs/proc/base.c
    fi
    if [ "${SUBLEVEL}" -ge 157 ]; then
        sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c
    fi

    # Copy SUSFS kernel files to common
    cp "${ROOT_DIR}/susfs4ksu/kernel_patches/fs/"* "${KERNEL_DIR}/common/fs/"
    cp "${ROOT_DIR}/susfs4ksu/kernel_patches/include/linux/"* "${KERNEL_DIR}/common/include/linux/"
    cp "${ROOT_DIR}/susfs4ksu/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch" ./

    # Apply KernelSU-Next SUSFS patch
    cd "${KERNEL_DIR}/KernelSU-Next"
    cp "${ROOT_DIR}/kernel_patches/wild/ksun-293ca01-susfs-v2.1.0-a14-6.1-ef16cbce.patch" ./
    patch -p1 < ksun-293ca01-susfs-v2.1.0-a14-6.1-ef16cbce.patch \
        || error "KSU SUSFS patch failed!"

    # Apply SUSFS main kernel patch
    cd "${KERNEL_DIR}/common"
    patch -p1 < "50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch" || true

    # Revert fake patches after SUSFS applied
    log "Reverting fake patches..."
    if [ "${SUBLEVEL}" -le 25 ]; then
        sed -i '/^#include <trace\/hooks\/sched.h>$/d' fs/proc/base.c
    fi
    if [ "${SUBLEVEL}" -le 141 ]; then
        sed -i '/^#include <linux\/dma-buf.h>$/d' fs/proc/base.c
    fi
    if [ "${SUBLEVEL}" -ge 157 ]; then
        sed -i '/^#include "internal.h"$/a #include <trace\/hooks\/blk.h>' fs/namespace.c
    fi

    # PAD fix for older sublevels
    if [ "${SUBLEVEL}" -le 75 ]; then
        sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c
    fi

    log "SUSFS setup ✅"
    echo "::endgroup::"

    # ======================================================
    # 🔓 MODULE VERSION CHECK BYPASS
    # ======================================================
    echo "::group::🔓 Module Version Check Bypass"
    cd "${KERNEL_DIR}"

    # For kernel 6.1: version check lives in kernel/module/version.c
    MODULE_VERSION_FILE="common/kernel/module/version.c"
    if [ -f "$MODULE_VERSION_FILE" ]; then
        sed -i '/bad_version:/{:a;n;/return 0;/{s/return 0;/return 1;/;b};ba}' \
            "$MODULE_VERSION_FILE"
        if grep -A 5 "bad_version:" "$MODULE_VERSION_FILE" | grep -q "return 1;"; then
            log "Module version check bypass applied ✅"
        else
            error "Module version check bypass failed!"
        fi
    else
        error "Module version file not found: ${MODULE_VERSION_FILE}"
    fi

    echo "::endgroup::"

    # ======================================================
    # 🗑️ REMOVE PROTECTED EXPORTS (Kleaf)
    # ======================================================
    echo "::group::🗑️ Remove Protected Exports"
    cd "${KERNEL_DIR}"

    rm -rf common/android/abi_gki_protected_exports_*

    if grep -q '"protected_exports_list"[[:space:]]*:[[:space:]]*"android/abi_gki_protected_exports_aarch64"' common/BUILD.bazel; then
        perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' common/BUILD.bazel
        log "BUILD.bazel protected_exports_list removed ✅"
    fi

    if grep -q '^protected_modules = ' common/modules.bzl; then
        sed -i 's/protected_modules = \[.*\]/protected_modules = []/' common/modules.bzl
        log "modules.bzl protected_modules cleared ✅"
    fi

    echo "::endgroup::"

    # ======================================================
    # 📝 BUILD FRAGMENT
    # ======================================================
    echo "::group::📝 Build Fragment"

    cat > "$FRAGMENT" << 'FRAGMENT_EOF'
# Version
CONFIG_LOCALVERSION=""
# CONFIG_LOCALVERSION_AUTO is not set

# Mountify Support
CONFIG_OVERLAY_FS=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y

# KPatch-Next Support
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# Droidspaces
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_DEVTMPFS=y

# KernelSU
CONFIG_KSU=y

# KernelSU SUSFS
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y

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
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_BITMAP_IPMAC=y
CONFIG_IP_SET_BITMAP_PORT=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_IPMARK=y
CONFIG_IP_SET_HASH_IPPORT=y
CONFIG_IP_SET_HASH_IPPORTIP=y
CONFIG_IP_SET_HASH_IPPORTNET=y
CONFIG_IP_SET_HASH_IPMAC=y
CONFIG_IP_SET_HASH_MAC=y
CONFIG_IP_SET_HASH_NETPORTNET=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETNET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_HASH_NETIFACE=y
CONFIG_IP_SET_LIST_SET=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
FRAGMENT_EOF

    # Copy to Kleaf fragment location
    cp "$FRAGMENT" "${KERNEL_DIR}/common/arch/arm64/configs/luminaire.fragment"
    log "Fragment ready ✅"
    echo "::endgroup::"

    # ======================================================
    # 🏷️ KERNEL BRANDING
    # ======================================================
    echo "::group::🏷️ Kernel Branding"
    cd "${KERNEL_DIR}/common"

    # Append -Luminaire to version string
    tac scripts/setlocalversion | awk '!seen && /^echo / {seen=1; next} 1' \
        | tac > scripts/setlocalversion.tmp
    mv scripts/setlocalversion.tmp scripts/setlocalversion
    echo 'echo "-Luminaire"' >> scripts/setlocalversion
    chmod +x scripts/setlocalversion

    # Clear scmversion file
    : > .scmversion

    # Set reproducible timestamp from last commit
    COMMIT_TIMESTAMP=$(git log -1 --format=%ct 2>/dev/null || echo "$(date +%s)")
    export SOURCE_DATE_EPOCH=$COMMIT_TIMESTAMP
    export KBUILD_BUILD_TIMESTAMP="@${COMMIT_TIMESTAMP}"
    echo "SOURCE_DATE_EPOCH=${COMMIT_TIMESTAMP}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "KBUILD_BUILD_TIMESTAMP=@${COMMIT_TIMESTAMP}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    log "Kernel branding applied ✅"
    echo "::endgroup::"

    # ======================================================
    # 🏗️ BUILD KERNEL (Kleaf)
    # ======================================================
    echo "::group::🏗️ Build Kernel"
    cd "${KERNEL_DIR}"

    export KBUILD_BUILD_USER="$BUILD_USER"
    export KBUILD_BUILD_HOST="$BUILD_HOST"

    mkdir -p "$BAZEL_CACHE_DIR" "$LD_CACHE_DIR"

    # LD wrapper for ThinLTO cache
    cat > "${KERNEL_DIR}/common/ld-wrapper" << 'LDWRAP_EOF'
#!/bin/bash
exec ld.lld "$@" --thinlto-cache-dir="$LD_CACHE_DIR" --thinlto-jobs="$(nproc --all)"
LDWRAP_EOF
    chmod +x "${KERNEL_DIR}/common/ld-wrapper"
    export LD="${KERNEL_DIR}/common/ld-wrapper"
    export HOSTLD="${KERNEL_DIR}/common/ld-wrapper"

    log "Building kernel using Kleaf/Bazel..."
    START_TIME=$(date +%s)

    # Heartbeat to prevent CI timeout
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

    tools/bazel build \
        --linkopt="--thinlto-cache-dir=${LD_CACHE_DIR}" \
        --config=fast \
        --defconfig_fragment=//common:arch/arm64/configs/luminaire.fragment \
        --disk_cache="${BAZEL_CACHE_DIR}" \
        //common:kernel_aarch64 \
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

    # Kleaf output
    IMAGE_PATH="${KERNEL_DIR}/bazel-bin/common/kernel_aarch64/Image"
    # Fallback to legacy output path
    [ -f "$IMAGE_PATH" ] || IMAGE_PATH="${KERNEL_DIR}/out/${ANDROID_VERSION}-${KERNEL_VERSION}/dist/Image"
    [ -f "$IMAGE_PATH" ] || error "Kernel Image not found!"

    cp "$IMAGE_PATH" "${AK3_DIR}/Image"

    DATE=$(date +"%b%d")
    ZIP_NAME="LuminaireProtocol-KSU-${DATE}R${GITHUB_RUN_NUMBER:-0}.zip"
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
KSU   : ${KSU_VERSION:-N/A} (${KSU_GIT_TAG:-N/A})
Date  : $(date +'%d %b %Y')" \
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
