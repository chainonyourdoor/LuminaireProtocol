#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE — ADIOS (Adaptive Deadline I/O Scheduler)
# by Masahito Suzuki (firelzrd)
# Repo: https://github.com/firelzrd/adios
# ======================================================

ADIOS_PATCH="${PATCHES_DIR}/luminaire/adios-v3.2.0.patch"

log "📦 Applying ADIOS I/O scheduler patch..."
[ -f "$ADIOS_PATCH" ] || error "ADIOS: not backported for kernel ${KERNEL_VERSION} yet (expected ${ADIOS_PATCH}) — this feature should have been gated out before reaching here (check run_luminaire()'s support map)."

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
    cat >> "$DEFCONFIG_FILE" << 'EOF'
# ADIOS I/O scheduler (Luminaire)
CONFIG_MQ_IOSCHED_ADIOS=y
CONFIG_MQ_IOSCHED_DEFAULT_ADIOS=y
EOF
    log "ADIOS: CONFIG_MQ_IOSCHED_ADIOS + DEFAULT_ADIOS enabled ✅"
fi

# See BORE_VERSION in bore.sh for why this is derived, not hardcoded.
ADIOS_VERSION="$(basename "$ADIOS_PATCH" .patch | sed 's/^adios-//')"
echo "ADIOS_VERSION=${ADIOS_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "ADIOS I/O scheduler integrated ✅"
