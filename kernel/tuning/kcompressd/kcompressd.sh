#!/usr/bin/env bash

KCOMPRESSD_PATCH="${PATCHES_DIR}/tuning/kcompressd-v0.5.patch"

log "⚙️ Applying Kcompressd patch..."
[ -f "$KCOMPRESSD_PATCH" ] || error "kcompressd: not backported for kernel ${KERNEL_VERSION} yet (expected ${KCOMPRESSD_PATCH}) — this feature should have been gated out before reaching here (check run_tuning()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KCOMPRESSD_PATCH" > /dev/null 2>&1; then
    log "kcompressd: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$KCOMPRESSD_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$KCOMPRESSD_PATCH" \
        || error "kcompressd: patch apply failed!"
    log "kcompressd: patch applied ✅"
else
    error "kcompressd: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

KCOMPRESSD_VERSION="$(basename "$KCOMPRESSD_PATCH" .patch | sed 's/^kcompressd-//')"
echo "KCOMPRESSD_VERSION=${KCOMPRESSD_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "Kcompressd integrated ✅"
