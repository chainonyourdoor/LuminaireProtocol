#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE — UFS / WriteBooster stable catch-up
# Cherry-picked/adapted from linux-6.1.y (gregkh/linux)
# ======================================================

UFS_WRITEBOOSTER_CATCHUP_PATCH="${PATCHES_DIR}/luminaire/ufs_writebooster_catchup.patch"

log "🩹 Applying UFS / WriteBooster stable catch-up..."
[ -f "$UFS_WRITEBOOSTER_CATCHUP_PATCH" ] || error "UFS/WriteBooster catch-up: not backported for kernel ${KERNEL_VERSION} yet (expected ${UFS_WRITEBOOSTER_CATCHUP_PATCH}) — this feature should have been gated out before reaching here (check run_luminaire()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$UFS_WRITEBOOSTER_CATCHUP_PATCH" > /dev/null 2>&1; then
    log "UFS/WriteBooster catch-up: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$UFS_WRITEBOOSTER_CATCHUP_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$UFS_WRITEBOOSTER_CATCHUP_PATCH" \
        || error "UFS/WriteBooster catch-up: patch apply failed!"
    log "UFS/WriteBooster catch-up: patch applied ✅"
else
    error "UFS/WriteBooster catch-up: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

log "UFS / WriteBooster stable catch-up integrated ✅"
