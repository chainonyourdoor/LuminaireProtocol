#!/usr/bin/env bash

ADIOS_PATCH="${PATCHES_DIR}/tuning/adios-v3.2.0.patch"
ADIOS_TUNABLE_PATCH="${PATCHES_DIR}/tuning/adios-tunable-v1.patch"

log "📦 Applying ADIOS I/O scheduler patch (with tunable latency-model sysfs)..."
[ -f "$ADIOS_PATCH" ] || error "ADIOS: not backported for kernel ${KERNEL_VERSION} yet (expected ${ADIOS_PATCH}) — this feature should have been gated out before reaching here (check run_tuning()'s support map)."
[ -f "$ADIOS_TUNABLE_PATCH" ] || error "ADIOS: tunable patch missing (expected ${ADIOS_TUNABLE_PATCH})."

# Kept as two sequential patch files/applies (not one merged file): both
# diffs touch block/adios.c, and GNU patch's --dry-run doesn't persist
# changes between hunks within a single invocation, so a merged file
# fails the dry-run-based already-applied check below even though the
# real (non-dry-run) apply would succeed. Splitting keeps each file's
# own dry-run check valid. Still one log group, one feature.
if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ADIOS_PATCH" > /dev/null 2>&1; then
    log "ADIOS: base patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$ADIOS_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ADIOS_PATCH" \
        || error "ADIOS: base patch apply failed!"
    log "ADIOS: base patch applied ✅"
else
    error "ADIOS: base patch does not apply cleanly — conflict or unsupported kernel source!"
fi

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ADIOS_TUNABLE_PATCH" > /dev/null 2>&1; then
    log "ADIOS: tunable patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$ADIOS_TUNABLE_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ADIOS_TUNABLE_PATCH" \
        || error "ADIOS: tunable patch apply failed!"
    log "ADIOS: tunable patch applied ✅"
else
    error "ADIOS: tunable patch does not apply cleanly — conflict or unsupported kernel source!"
fi

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_MQ_IOSCHED_ADIOS=y" "$DEFCONFIG_FILE"; then
    cat >> "$DEFCONFIG_FILE" << 'DEFEOF'
# ADIOS I/O scheduler (Luminaire) — selectable, not default.
CONFIG_MQ_IOSCHED_ADIOS=y
DEFEOF
    log "ADIOS: CONFIG_MQ_IOSCHED_ADIOS enabled (not set as default) ✅"
fi

ADIOS_VERSION="$(basename "$ADIOS_PATCH" .patch | sed 's/^adios-//')-tunable-lm"
echo "ADIOS_VERSION=${ADIOS_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "ADIOS I/O scheduler (with tunable latency-model sysfs) integrated ✅"
