#!/usr/bin/env bash

LE9UO_PATCH="${PATCHES_DIR}/tuning/le9uo-v1.15.patch"

log "🛡️ Applying le9uo working set protection patch..."
[ -f "$LE9UO_PATCH" ] || error "le9uo: not backported for kernel ${KERNEL_VERSION} yet (expected ${LE9UO_PATCH}) — this feature should have been gated out before reaching here (check run_tuning()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$LE9UO_PATCH" > /dev/null 2>&1; then
    log "le9uo: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$LE9UO_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$LE9UO_PATCH" \
        || error "le9uo: patch apply failed!"
    log "le9uo: patch applied ✅"
else
    error "le9uo: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
sed -i '/^# le9uo Working Set Protection (Luminaire) — active from boot$/d; /^CONFIG_WORKINGSET_PROTECTION_ENABLED=y$/d; /^CONFIG_ANON_MIN_RATIO=[0-9]*$/d; /^CONFIG_CLEAN_LOW_RATIO=[0-9]*$/d; /^CONFIG_CLEAN_MIN_RATIO=[0-9]*$/d' "$DEFCONFIG_FILE"
cat >> "$DEFCONFIG_FILE" << 'DEFEOF'
# le9uo Working Set Protection (Luminaire) — active from boot
CONFIG_WORKINGSET_PROTECTION_ENABLED=y
CONFIG_ANON_MIN_RATIO=5
CONFIG_CLEAN_LOW_RATIO=0
CONFIG_CLEAN_MIN_RATIO=5
DEFEOF
log "le9uo: defconfig forced (protection active from first boot, anon/clean min ratio 5%) ✅"

LE9UO_VERSION="$(basename "$LE9UO_PATCH" .patch | sed 's/^le9uo-//')"
echo "LE9UO_VERSION=${LE9UO_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "le9uo Working Set Protection integrated ✅"
