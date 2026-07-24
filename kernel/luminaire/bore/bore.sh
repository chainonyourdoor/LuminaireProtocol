#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE — BORE (Burst-Oriented Response Enhancer)
# CPU scheduler by Masahito Suzuki (firelzrd)
# Repo: https://github.com/firelzrd/bore-scheduler
#
# ⚠️ TESTING: temporarily pointed at the v6.8.0-rc1 partial backport
# (see docs/CODEX.md for provenance/status) instead of the proven
# v5.3.0 patch, to boot-test on real hardware. v5.3.0 is kept in
# kernel/patches/android14-6.1/luminaire/bore-v5.3.0.patch — revert
# BORE_PATCH below to it if v6.8.0-rc1 fails to boot.
# ======================================================

BORE_PATCH="${PATCHES_DIR}/luminaire/bore-v6.8.0-rc1.patch"

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

# Derived from the patch filename (bore-<version>.patch) rather than a
# separate hardcoded string, so it can't drift from BORE_PATCH above.
# Consumed by release/telegram/caption.py to show the active version
# in release notes instead of a generic "Active".
BORE_VERSION="$(basename "$BORE_PATCH" .patch | sed 's/^bore-//')"
echo "BORE_VERSION=${BORE_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "BORE CPU scheduler integrated ✅"
