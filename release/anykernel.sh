#!/usr/bin/env bash

# ======================================================
# 📦 RELEASE — ANYKERNEL3 PACKAGING
# ======================================================

case "${KERNEL_VARIANT}" in
    VANILLA)  ZIP_VARIANT_TAG="VANILLA" ;;
    RESUKISU) ZIP_VARIANT_TAG="RESUKISU" ;;
    SUKISU)   ZIP_VARIANT_TAG="SUKISU" ;;
    KSUNEXT)  ZIP_VARIANT_TAG="KSUNEXT" ;;
    *)        ZIP_VARIANT_TAG="${KERNEL_VARIANT}" ;;
esac
[ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ] && ZIP_VARIANT_TAG="${ZIP_VARIANT_TAG}+SUSFS"
[ -n "${SUBLEVEL:-}" ] || error "SUBLEVEL is not set — branding.sh may not have run correctly!"
ZIP_NAME="Ak3-${KERNEL_VERSION}.${SUBLEVEL}-${ZIP_VARIANT_TAG}-R${GITHUB_RUN_NUMBER:-0}.zip"
export ZIP_NAME

if [ "${USE_AK3_CACHE}" = "true" ] && [ -d "${HOME}/ak3-cache" ]; then
    cp -a "${HOME}/ak3-cache/." "${TOOL_AK3_DIR}/"
    log "AnyKernel3 restored from cache ✅ ($(cache_freshness_note))"
else
    retry 3 run_quiet git clone -q --depth=1 \
        https://github.com/chainonyourdoor/AnyKernel3-Luminaire.git "$TOOL_AK3_DIR" \
        || error "Failed to clone AK3! (see output above)"
    mkdir -p "${HOME}/ak3-cache"
    cp -a "${TOOL_AK3_DIR}/." "${HOME}/ak3-cache/"
fi

[ -d "$TOOL_AK3_DIR" ] || error "AK3 directory missing after clone/cache restore — aborting packaging"

KERNEL_IMG=""
BOOT_SEARCH_DIR="${OUT_DIR}/arch/${ARCH}/boot"

for img in Image Image.gz Image.gz-dtb Image-dtb; do
    BOOT_PATH="${BOOT_SEARCH_DIR}/${img}"
    if [ -f "$BOOT_PATH" ]; then
        KERNEL_IMG="$BOOT_PATH"
        log "Kernel image: $img (from ${BUILD_SYSTEM})"
        break
    fi
done
[ -z "$KERNEL_IMG" ] && error "Kernel image not found! Searched ${BOOT_SEARCH_DIR}/ for: Image, Image.gz, Image.gz-dtb, Image-dtb"

cp "$KERNEL_IMG" "${TOOL_AK3_DIR}/"

# Kasumi is an out-of-tree LKM, not something AK3's ramdisk-patch flow can
# auto-load like an in-tree CONFIG option — it ships as a plain .ko in the
# zip under modules/, for manual `insmod`/`ksud insmod` on-device. No
# auto-load hook here on purpose (see kernel/addons/kasumi/kasumi.sh: this
# is explicitly experimental/opt-in, not something that should silently
# start hooking VFS/syscall paths on every boot).
if [ -n "${KASUMI_KO:-}" ] && [ -f "${KASUMI_KO}" ]; then
    mkdir -p "${TOOL_AK3_DIR}/modules"
    cp "$KASUMI_KO" "${TOOL_AK3_DIR}/modules/"
    log "Kasumi: kasumi_lkm.ko included in zip under modules/ (manual insmod required) ✅"
fi

ZIP_PATH="/tmp/${ZIP_NAME}"
export ZIP_PATH ZIP_NAME
cd "$TOOL_AK3_DIR"
zip -r9 "$ZIP_PATH" . -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE" \
    || error "ZIP creation failed!"
[ -f "$ZIP_PATH" ] || error "ZIP file not found after creation!"
cd "$ROOT_DIR"

log "ZIP ready: ${ZIP_NAME} ✅"
echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
echo "ZIP_PATH=${ZIP_PATH}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
