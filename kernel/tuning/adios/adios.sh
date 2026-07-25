#!/usr/bin/env bash

ADIOS_PATCH="${PATCHES_DIR}/tuning/adios-v3.2.0.patch"

log "📦 Applying ADIOS I/O scheduler patch..."
[ -f "$ADIOS_PATCH" ] || error "ADIOS: not backported for kernel ${KERNEL_VERSION} yet (expected ${ADIOS_PATCH}) — this feature should have been gated out before reaching here (check run_tuning()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ADIOS_PATCH" > /dev/null 2>&1; then
    log "ADIOS: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$ADIOS_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ADIOS_PATCH" \
        || error "ADIOS: patch apply failed!"
    log "ADIOS: patch applied ✅"
else
    error "ADIOS: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_MQ_IOSCHED_ADIOS=y" "$DEFCONFIG_FILE"; then
    cat >> "$DEFCONFIG_FILE" << 'DEFEOF'
# ADIOS I/O scheduler (Luminaire) — compiled in as a selectable option
# only. Deliberately NOT setting CONFIG_MQ_IOSCHED_DEFAULT_ADIOS=y here:
# this project adds scheduler choices, it doesn't force one on the user.
# mq-deadline remains the default (see this file's CODEX.md entry for
# why the backport preserves that fallback). Users who want ADIOS can
# select it themselves via /sys/block/*/queue/scheduler.
CONFIG_MQ_IOSCHED_ADIOS=y
DEFEOF
    log "ADIOS: CONFIG_MQ_IOSCHED_ADIOS enabled (not set as default) ✅"
fi

ADIOS_VERSION="$(basename "$ADIOS_PATCH" .patch | sed 's/^adios-//')"
echo "ADIOS_VERSION=${ADIOS_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "ADIOS I/O scheduler integrated ✅"
