#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — SukiSU-Ultra
# ======================================================
# Repo: https://github.com/SukiSU-Ultra/SukiSU-Ultra

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Integrating SukiSU-Ultra..."
cd "$KERNEL_SRC"
SUKISU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh") \
    || error "SukiSU-Ultra: failed to download setup.sh!"
[ -n "$SUKISU_SETUP" ] || error "SukiSU-Ultra: setup.sh is empty!"
echo "$SUKISU_SETUP" | grep -q "^#!" || error "SukiSU-Ultra: setup.sh looks invalid (no shebang)!"
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    SUKISU_REF="${SUKISU_BUILTIN_REF:-builtin}"
fi
if [ -n "${SUKISU_REF:-}" ]; then
    log "Pinning SukiSU-Ultra to ${SUKISU_REF}"
    echo "$SUKISU_SETUP" | bash -s -- "$SUKISU_REF" || error "SukiSU-Ultra: setup.sh failed!"
else
    echo "$SUKISU_SETUP" | bash || error "SukiSU-Ultra: setup.sh failed!"
fi
[ -d "${KERNEL_SRC}/KernelSU" ] || error "SukiSU-Ultra: KernelSU dir not found after setup!"
cd "$ROOT_DIR"
log "SukiSU-Ultra integrated ✅"

log "Applying Luminaire branding..."
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    BRANDING_TARGET="${KSU_DIR}/kernel/Makefile"
else
    BRANDING_TARGET="${KSU_DIR}/kernel/Kbuild"
fi
python3 "${PATCHER_DIR}/branding.py" "$BRANDING_TARGET" \
    || error "SukiSU-Ultra: branding patch failed!"
log "Branding applied ✅"

SUKISU_GIT_COMMIT_COUNT=$(git -C "$KSU_DIR" rev-list --count main 2>/dev/null || echo "")
SUKISU_GITHUB_COMMITS=$(curl -sI --connect-timeout 10 --max-time 15 \
    "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/commits?sha=main&per_page=1" 2>/dev/null \
    | grep -i "link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p')
SUKISU_LOCAL_COUNT="${SUKISU_GITHUB_COMMITS:-$SUKISU_GIT_COMMIT_COUNT}"
if [ -n "$SUKISU_LOCAL_COUNT" ]; then
    KSU_VERSION_CODE=$((40000 + SUKISU_LOCAL_COUNT - 2815))
else
    KSU_VERSION_CODE=13000
fi

SUKISU_GIT_LATEST_TAG=$(git -C "$KSU_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
SUKISU_GITHUB_VER=$(curl -s --connect-timeout 10 --max-time 15 \
    "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/releases/latest" 2>/dev/null \
    | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    SUKISU_DEFAULT_TAG="4.1.2"
else
    SUKISU_DEFAULT_TAG="4.1.3"
fi
KSU_TAG_NAME="v${SUKISU_GITHUB_VER:-${SUKISU_GIT_LATEST_TAG:-$SUKISU_DEFAULT_TAG}}"

KSU_UAPI_VERSION=$(grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "${KSU_DIR}/uapi/supercall.h" 2>/dev/null || echo "")

if [ -n "$KSU_UAPI_VERSION" ]; then
    SUKISU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE}/${KSU_UAPI_VERSION})"
else
    SUKISU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE})"
fi
echo "SUKISU_VERSION_DISPLAY=${SUKISU_VERSION_DISPLAY}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "Version: ${SUKISU_VERSION_DISPLAY}"

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
fi
log "Configs enabled ✅"

log "SukiSU-Ultra ready ✅"
