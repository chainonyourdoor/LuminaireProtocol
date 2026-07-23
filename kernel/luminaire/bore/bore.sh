#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE — BORE (Burst-Oriented Response Enhancer)
# CPU scheduler by Masahito Suzuki (firelzrd)
# Repo: https://github.com/firelzrd/bore-scheduler
# ======================================================

BORE_PATCH="${VERSION_PATCH_DIR}/patches/luminaire/bore-v5.3.0.patch"

log "🔥 Applying BORE CPU scheduler patch..."
[ -f "$BORE_PATCH" ] || error "BORE: not backported for kernel ${KERNEL_VERSION} yet (expected ${BORE_PATCH}) — this feature should have been gated out before reaching here (check run_luminaire()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$BORE_PATCH" > /dev/null 2>&1; then
    log "BORE: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$BORE_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$BORE_PATCH" \
        || error "BORE: patch apply failed!"
    log "BORE: patch applied ✅"
else
    error "BORE: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_SCHED_BORE=y" "$DEFCONFIG_FILE"; then
    cat >> "$DEFCONFIG_FILE" << 'EOF'
# BORE CPU scheduler (Luminaire)
CONFIG_SCHED_BORE=y
EOF
    log "BORE: CONFIG_SCHED_BORE enabled ✅"
fi

log "BORE CPU scheduler integrated ✅"
