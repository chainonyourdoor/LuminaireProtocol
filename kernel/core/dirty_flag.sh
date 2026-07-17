#!/usr/bin/env bash

# ======================================================
# 🧹 CLEAN DIRTY FLAGS
# ======================================================

sed -i 's/-dirty//' "${KERNEL_SRC}/scripts/setlocalversion"

cd "${KERNEL_SRC}"
git config --local user.name "${BUILD_USER:-chainonyourdoor}"
git config --local user.email "${BUILD_USER:-chainonyourdoor}@users.noreply.github.com"
git add . > /dev/null 2>&1 && { git commit --amend --no-edit --quiet 2>/dev/null || git commit -m "Luminaire: Clean dirty flags" --quiet; } \
    || warn "dirty_flag: git commit failed (tree may already be clean or git not initialized — dirty flag may persist in version string)"
cd "${ROOT_DIR}"
log "Dirty flags cleaned ✅"
