#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE — Workqueue stable catch-up
# Cherry-picked/adapted from linux-6.1.y (gregkh/linux)
# ======================================================

WORKQUEUE_CATCHUP_PATCH="${PATCHES_DIR}/luminaire/workqueue_catchup.patch"

log "🩹 Applying Workqueue stable catch-up..."
[ -f "$WORKQUEUE_CATCHUP_PATCH" ] || error "Workqueue catch-up: not backported for kernel ${KERNEL_VERSION} yet (expected ${WORKQUEUE_CATCHUP_PATCH}) — this feature should have been gated out before reaching here (check run_luminaire()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$WORKQUEUE_CATCHUP_PATCH" > /dev/null 2>&1; then
    log "Workqueue catch-up: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$WORKQUEUE_CATCHUP_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$WORKQUEUE_CATCHUP_PATCH" \
        || error "Workqueue catch-up: patch apply failed!"
    log "Workqueue catch-up: patch applied ✅"
else
    error "Workqueue catch-up: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

log "Workqueue stable catch-up integrated ✅"
