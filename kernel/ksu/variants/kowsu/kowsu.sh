#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KowSU
# ======================================================
# Repo: https://github.com/KOWX712/KernelSU
# Note: KowSU's manager app (com.kowx712.supermanager) does not expose a
# separate kernel driver version field the way ReSukiSU's manager does, so
# Luminaire branding is intentionally NOT applied for this variant (cosmetic
# only, no functional impact — see project decision).

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Integrating KowSU..."
cd "$KERNEL_SRC"
KOWSU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/KOWX712/KernelSU/main/kernel/setup.sh") \
    || error "KowSU: failed to download setup.sh!"
[ -n "$KOWSU_SETUP" ] || error "KowSU: setup.sh is empty!"
echo "$KOWSU_SETUP" | grep -q "^#!" || error "KowSU: setup.sh looks invalid (no shebang)!"
if [ -n "${KOWSU_REF:-}" ]; then
    log "Pinning KowSU to ${KOWSU_REF}"
    echo "$KOWSU_SETUP" | bash -s -- "$KOWSU_REF" || error "KowSU: setup.sh failed!"
else
    echo "$KOWSU_SETUP" | bash || error "KowSU: setup.sh failed!"
fi
[ -d "$KSU_DIR" ] || error "KowSU: KernelSU dir not found after setup!"
verify_pinned_ref "KowSU" "$KSU_DIR" "${KOWSU_REF:-}"
cd "$ROOT_DIR"
log "KowSU integrated ✅"

KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --abbrev=0 --tags 2>/dev/null || echo "v0.0.1")
KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION))
KSU_UAPI_VERSION=$(grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "${KSU_DIR}/uapi/supercall.h" 2>/dev/null || echo "")

if [ -n "$KSU_UAPI_VERSION" ]; then
    KOWSU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE}/${KSU_UAPI_VERSION})"
else
    KOWSU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE})"
fi
echo "KOWSU_VERSION_DISPLAY=${KOWSU_VERSION_DISPLAY}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "Version: ${KOWSU_VERSION_DISPLAY}"

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIGS
fi
log "Configs enabled ✅"

log "KowSU ready ✅"
