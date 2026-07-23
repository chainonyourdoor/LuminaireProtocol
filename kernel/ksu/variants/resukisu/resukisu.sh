#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — ReSukiSU
# ======================================================
# Repo: https://github.com/ReSukiSU/ReSukiSU

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Integrating ReSukiSU..."
cd "$KERNEL_SRC"
RESUKISU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh") \
    || error "ReSukiSU: failed to download setup.sh!"
[ -n "$RESUKISU_SETUP" ] || error "ReSukiSU: setup.sh is empty!"
echo "$RESUKISU_SETUP" | grep -q "^#!" || error "ReSukiSU: setup.sh looks invalid (no shebang)!"
if [ -n "${RESUKISU_REF:-}" ]; then
    log "Pinning ReSukiSU to ${RESUKISU_REF}"
    echo "$RESUKISU_SETUP" | bash -s -- "$RESUKISU_REF" || error "ReSukiSU: setup.sh failed!"
else
    echo "$RESUKISU_SETUP" | bash || error "ReSukiSU: setup.sh failed!"
fi
[ -d "${KERNEL_SRC}/KernelSU" ] || error "ReSukiSU: KernelSU dir not found after setup!"
cd "$ROOT_DIR"
log "ReSukiSU integrated ✅"

log "Applying Luminaire branding..."
python3 "${PATCHER_DIR}/branding.py" "${KSU_DIR}/kernel/Kbuild" \
    || error "ReSukiSU: branding patch failed!"
log "Branding applied ✅"

KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --abbrev=0 --tags 2>/dev/null || echo "v4.1.0")
KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION + 700))
KSU_UAPI_VERSION=$(grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "${KSU_DIR}/uapi/supercall.h" 2>/dev/null || echo "")

if [ -n "$KSU_UAPI_VERSION" ]; then
    RESUKISU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE}/${KSU_UAPI_VERSION})"
else
    RESUKISU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE})"
fi
echo "RESUKISU_VERSION_DISPLAY=${RESUKISU_VERSION_DISPLAY}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "Version: ${RESUKISU_VERSION_DISPLAY}"

log "Patching multi-manager support..."
python3 "${PATCHER_DIR}/multimanager.py" \
    "${KSU_DIR}/kernel/manager/manager_sign.h" \
    "${KSU_DIR}/kernel/manager/apk_sign.c" \
    || error "ReSukiSU: multi-manager patch failed!"
log "Multi-manager patched ✅"

log "Patching KSU-Next manager compat..."
python3 "${PATCHER_DIR}/ksunext_compat.py" \
    "${KSU_DIR}/kernel/supercall/dispatch.c" \
    || error "ReSukiSU: KSU-Next compat patch failed!"
log "KSU-Next compat patched ✅"

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
fi
log "Configs enabled ✅"

log "ReSukiSU ready ✅"
