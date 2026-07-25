#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS — shared apply logic (any KSU fork, android15-6.6)
# ======================================================
# Repo: https://gitlab.com/simonpunk/susfs4ksu
#
# NOTE: unlike the android12-5.10/android13-5.15/android14-6.1
# copies of this script, this one intentionally does NOT carry the
# "SUBLEVEL >= 157 → strip/restore blk.h in namespace.c" workaround.
# That workaround exists because a specific point in Linux 6.1.x's
# upstream history dropped a trace/hooks/blk.h include that SuSFS's
# patch context depends on — it's tied to 6.1's own commit history,
# not a general GKI/SuSFS quirk, so blindly carrying it over to 6.6
# (an entirely different source tree) would be guessing. If patching
# ever fails here for a similar reason, add an equivalent guard after
# confirming the actual upstream diff for the affected 6.6.x sublevel
# — don't re-add this one unmodified.

if [ "$KERNEL_VARIANT" = "SUKISU" ]; then
    SUSFS_REF="${SUSFS_SUKISU_REF:-}"
    [ -n "$SUSFS_REF" ] || warn "SuSFS+SukiSU: no pin resolved — build will likely fail (see wishlist for known-good combos)"
    SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
    SUSFS_BRANCH="gki-android15-6.6"
elif [ "$KERNEL_VARIANT" = "KSUNEXT" ]; then
    SUSFS_REF="${SUSFS_KSUNEXT_REF:-}"
    SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
    SUSFS_BRANCH="gki-android15-6.6-dev"
else
    SUSFS_REF="${SUSFS_RESUKISU_REF:-}"
    SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
    SUSFS_BRANCH="gki-android15-6.6"
fi

KSU_DIR="${KSU_DIR:-${KERNEL_SRC}/KernelSU}"
SUSFS_DIR="/tmp/susfs4ksu"
KSU_SHARED_DIR="${LUMINAIRE_PATCH_DIR}/kernel/ksu"

log "Cloning SuSFS (${SUSFS_BRANCH})..."
[ -d "$SUSFS_DIR" ] && rm -rf "$SUSFS_DIR"
git config --global http.connectTimeout 30
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
if [ -n "${SUSFS_REF:-}" ]; then
    log "Pinning SuSFS to ${SUSFS_REF}"
    mkdir -p "$SUSFS_DIR"
    (
        cd "$SUSFS_DIR"
        git init -q
        git remote add origin "$SUSFS_REPO"
        run_quiet git fetch --depth=1 origin "$SUSFS_REF" && git checkout -q FETCH_HEAD
    ) || {
        warn "SuSFS: server doesn't support fetching bare SHA — falling back to full clone"
        rm -rf "$SUSFS_DIR"
        retry 3 run_quiet git clone -q -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
            || error "SuSFS: full clone fallback failed after 3 attempts!"
        (cd "$SUSFS_DIR" && git checkout -q "$SUSFS_REF") \
            || error "SuSFS: ${SUSFS_REF} not found on ${SUSFS_BRANCH} even after full clone!"
    }
else
    retry 3 run_quiet git clone -q --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
        || error "SuSFS clone failed after 3 attempts!"
fi

log "Copying SuSFS source files..."
cp "${SUSFS_DIR}/kernel_patches/fs/susfs.c"                  "${KERNEL_SRC}/fs/susfs.c"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs.h"       "${KERNEL_SRC}/include/linux/susfs.h"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs_def.h"   "${KERNEL_SRC}/include/linux/susfs_def.h"
log "SuSFS source files copied ✅"

log "Applying SuSFS kernel patch..."
KERNEL_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
if [ ! -f "$KERNEL_PATCH" ]; then
    warn "SuSFS kernel patch not found at ${KERNEL_PATCH} — skipping patch step, continuing with Kconfig/config setup"
elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KERNEL_PATCH" > /dev/null 2>&1; then
    log "SuSFS kernel patch already applied, skipping."
else
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$KERNEL_PATCH" \
        && log "SuSFS kernel patch applied ✅" \
        || warn "SuSFS kernel patch: some hunks failed — continuing"

    find "$KERNEL_SRC" -name "*.rej" -delete 2>/dev/null || true
fi

log "Fixing namespace.c susfs declarations (safety fallback)..."
python3 "${KSU_SHARED_DIR}/fix_namespace.py" "${KERNEL_SRC}/fs/namespace.c" \
    || error "SuSFS: namespace.c fix failed!"
log "namespace.c fixed ✅"

if [ "$KERNEL_VARIANT" = "KSUNEXT" ]; then
    SELINUX_HIDE_C="${KSU_DIR}/kernel/feature/selinux_hide.c"
    if [ -f "$SELINUX_HIDE_C" ]; then
        log "Fixing KernelSU-Next with_policy static/extern linkage (kernel >=6.6 only, safety fallback)..."
        python3 "${KSU_SHARED_DIR}/fix_ksunext_with_policy_linkage.py" "$SELINUX_HIDE_C" \
            || error "SuSFS: KernelSU-Next with_policy linkage fix failed!"
    fi
fi

rm -rf "$SUSFS_DIR"

log "Ensuring KSU_SUSFS Kconfig declarations exist..."
KSU_KCONFIG="${KSU_DIR}/kernel/Kconfig"
if [ -f "$KSU_KCONFIG" ] && grep -q "^config KSU_SUSFS$" "$KSU_KCONFIG"; then
    log "KSU_SUSFS already declared by this fork, skipping injection."
else
    python3 "${KSU_SHARED_DIR}/kconfig_inject.py" "$KSU_KCONFIG" \
        || error "SuSFS: Kconfig inject failed!"
    log "KSU_SUSFS Kconfig injected ✅"
fi

log "Enabling SuSFS configs..."
if ! grep -q "^CONFIG_KSU_SUSFS=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIGS
fi
log "SuSFS configs enabled ✅"

log "SuSFS integrated ✅"
