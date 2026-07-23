#!/usr/bin/env bash

if [ "${USE_KERNEL_CACHE}" = "true" ] && [ -d "${HOME}/kernel-cache/common" ]; then
    log "Restoring kernel source from cache..."
    cp -a "${HOME}/kernel-cache/." "${KERNEL_DIR}/"
    log "Kernel source restored ✅ ($(cache_freshness_note))"
else
    log "Cloning kernel source..."
    KERNEL_REPO_URL="https://github.com/chainonyourdoor/LuminaireKernel-${KERNEL_VERSION}"
    log "Source: ${KERNEL_REPO_URL} @ ${KERNEL_BRANCH}"
    git config --global http.connectTimeout 30
    git config --global http.lowSpeedLimit 1000
    git config --global http.lowSpeedTime 30
    retry 3 run_quiet git clone -q --depth=1 \
        -b "$KERNEL_BRANCH" \
        "$KERNEL_REPO_URL" \
        "${KERNEL_DIR}/common" || error "Failed to clone kernel! (see output above)"
    log "Saving to cache..."
    mkdir -p "${HOME}/kernel-cache"
    rsync -a --delete "${KERNEL_DIR}/" "${HOME}/kernel-cache/"
fi
