#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE — Schedutil stable catch-up
# Cherry-picked/adapted from linux-6.1.y (gregkh/linux)
# ======================================================

SCHEDUTIL_CATCHUP_PATCH="${PATCHES_DIR}/luminaire/schedutil_catchup.patch"

log "🩹 Applying Schedutil stable catch-up..."
[ -f "$SCHEDUTIL_CATCHUP_PATCH" ] || error "Schedutil catch-up: not backported for kernel ${KERNEL_VERSION} yet (expected ${SCHEDUTIL_CATCHUP_PATCH}) — this feature should have been gated out before reaching here (check run_luminaire()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$SCHEDUTIL_CATCHUP_PATCH" > /dev/null 2>&1; then
    log "Schedutil catch-up: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$SCHEDUTIL_CATCHUP_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$SCHEDUTIL_CATCHUP_PATCH" \
        || error "Schedutil catch-up: patch apply failed!"
    log "Schedutil catch-up: patch applied ✅"
else
    error "Schedutil catch-up: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

log "Schedutil stable catch-up integrated ✅"
