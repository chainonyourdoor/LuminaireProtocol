#!/usr/bin/env bash

# ======================================================
# 📦 RELEASE — ANYKERNEL3 PACKAGING
# ======================================================

ZIP_NAME="LuminaireAk3-${KERNEL_VERSION}.${SUBLEVEL}-${VARIANT}-R${GITHUB_RUN_NUMBER:-0}.zip"
export ZIP_NAME

if [ "${USE_AK3_CACHE}" = "true" ] && [ -d "${HOME}/ak3-cache" ]; then
    cp -a "${HOME}/ak3-cache/." "${TOOL_AK3_DIR}/"
    log "AnyKernel3 restored from cache ✅"
else
    git clone -q --depth=1 \
        https://github.com/chainonyourdoor/AnyKernel3-Luminaire.git "$TOOL_AK3_DIR" \
        || error "Failed to clone AK3!"
    mkdir -p "${HOME}/ak3-cache"
    cp -a "${TOOL_AK3_DIR}/." "${HOME}/ak3-cache/"
fi

KERNEL_IMG=""
BOOT_SEARCH_DIR="$([ "$BUILD_SYSTEM" = "KLEAF" ] && echo "$KLEAF_OUT_DIR" || echo "${OUT_DIR}/arch/${ARCH}/boot")"

for img in Image Image.gz Image.gz-dtb Image-dtb; do
    BOOT_PATH="${BOOT_SEARCH_DIR}/${img}"
    if [ -f "$BOOT_PATH" ]; then
        KERNEL_IMG="$BOOT_PATH"
        log "Kernel image: $img (from ${BUILD_SYSTEM})"
        break
    fi
done
[ -z "$KERNEL_IMG" ] && error "Kernel image not found!"

cp "$KERNEL_IMG" "${TOOL_AK3_DIR}/"

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
