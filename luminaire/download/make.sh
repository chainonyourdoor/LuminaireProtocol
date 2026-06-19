#!/usr/bin/env bash

# ======================================================
# 📥 DOWNLOAD — MAKE (Git Clone)
# ======================================================

if [ "${USE_KERNEL_CACHE}" = "true" ] && [ -d "${HOME}/kernel-cache/common" ]; then
    log "Restoring kernel source from cache..."
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
    rsync -a --delete "${KERNEL_DIR}/" "${HOME}/kernel-cache/"
fi
