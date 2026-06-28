#!/usr/bin/env bash

# ======================================================
# 🧹 CLEAN DIRTY FLAGS
# ======================================================

sed -i 's/-dirty//' "${KERNEL_SRC}/scripts/setlocalversion"

if [ -f "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl" ]; then
    sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" \
        "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
fi

if [ "$BUILD_SYSTEM" != "KLEAF" ]; then
    cd "${KERNEL_DIR}/common"
    git config --local user.name "chainonyourdoor"
    git config --local user.email "chainonyourdoor@gmail.com"
    git add . && { git commit --amend --no-edit 2>/dev/null || git commit -m "Luminaire: Clean dirty flags"; } \
        || warn "dirty_flag: git commit failed (tree may already be clean or git not initialized — dirty flag may persist in version string)"
    cd "${ROOT_DIR}"
fi
log "Dirty flags cleaned ✅"
