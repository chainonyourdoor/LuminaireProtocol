#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU-Next
# ======================================================
# Repo: https://github.com/KernelSU-Next/KernelSU-Next

# setup.sh clones into ${GKI_ROOT}/KernelSU-Next and symlinks
# drivers/kernelsu -> KernelSU-Next/kernel, unlike ReSukiSU/SukiSU-Ultra's
# setup.sh which both produce a "KernelSU" dir directly — KSU_DIR below is
# intentionally different from resukisu.sh/sukisu.sh for this reason.
KSU_DIR="${KERNEL_SRC}/KernelSU-Next"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ======================================================
# 1. KernelSU-Next
# ======================================================

log "Integrating KernelSU-Next..."
cd "$KERNEL_SRC"
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    # Official KernelSU-Next has no SUSFS-compatible hook API on its dev
    # branch (see susfs.sh) — pershoot's fork keeps a dev-susfs branch that
    # does, paired with their own susfs4ksu fork. Maintainer flags this
    # fork as not production-ready; tracked like any other candidate via
    # kernel/checkpoint/scout.sh.
    log "SUSFS enabled — using pershoot/KernelSU-Next's dev-susfs fork"
    KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh"
    KSUNEXT_SETUP_REF="${KSUNEXT_SUSFS_FORK_REF:-dev-susfs}"
else
    KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh"
    KSUNEXT_SETUP_REF="${KSUNEXT_REF:-}"
fi
KSUNEXT_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "$KSUNEXT_SETUP_URL") \
    || error "KernelSU-Next: failed to download setup.sh!"
[ -n "$KSUNEXT_SETUP" ] || error "KernelSU-Next: setup.sh is empty!"
echo "$KSUNEXT_SETUP" | grep -q "^#!" || error "KernelSU-Next: setup.sh looks invalid (no shebang)!"
if [ -n "$KSUNEXT_SETUP_REF" ]; then
    log "Pinning KernelSU-Next to ${KSUNEXT_SETUP_REF}"
    echo "$KSUNEXT_SETUP" | bash -s -- "$KSUNEXT_SETUP_REF" || error "KernelSU-Next: setup.sh failed!"
else
    echo "$KSUNEXT_SETUP" | bash || error "KernelSU-Next: setup.sh failed!"
fi
[ -d "$KSU_DIR" ] || error "KernelSU-Next: KernelSU-Next dir not found after setup!"
cd "$ROOT_DIR"
log "KernelSU-Next integrated ✅"

# ======================================================
# 2. Branding
# ======================================================

log "Applying Luminaire branding..."
python3 "${PATCHER_DIR}/branding.py" "${KSU_DIR}/kernel/Kbuild" \
    || error "KernelSU-Next: branding patch failed!"
log "Branding applied ✅"

# ======================================================
# 2b. Version string (for Telegram caption)
# ======================================================
# Official KernelSU-Next's Kbuild: KSU_VERSION = 30000 + rev-list --count
# HEAD, KSU_VERSION_TAG = `git describe --tags --abbrev=0` at HEAD (fallback
# v0.0.1). Simple and purely local, like ReSukiSU's formula.
#
# pershoot/KernelSU-Next's dev-susfs fork (used when SUSFS_ENABLED) computes
# both from a BASE_COMMIT instead of raw HEAD — the merge-base between HEAD
# and origin/<branch-with-suffix-stripped> (falls back to origin/main, then
# HEAD itself) — so fork-specific commits on top of upstream don't inflate
# the version number. Replicated here rather than simplified to raw HEAD,
# since that would give a different number than what's actually compiled.
# This fork is flagged not-production-ready upstream (see section 1's
# comment), so treat this version string as unverified until a real build
# confirms it.

if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    KSUNEXT_CUR_BRANCH=$(git -C "$KSU_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    KSUNEXT_BASE_BRANCH="${KSUNEXT_CUR_BRANCH%%-*}"
    KSUNEXT_BASE_COMMIT=$(git -C "$KSU_DIR" merge-base HEAD "refs/remotes/origin/${KSUNEXT_BASE_BRANCH}" 2>/dev/null \
        || git -C "$KSU_DIR" merge-base HEAD refs/remotes/origin/main 2>/dev/null \
        || echo HEAD)
else
    KSUNEXT_BASE_COMMIT="HEAD"
fi

KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count "$KSUNEXT_BASE_COMMIT" 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION))
KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --tags --abbrev=0 "$KSUNEXT_BASE_COMMIT" 2>/dev/null || echo "v0.0.1")
KSU_UAPI_VERSION=$(grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "${KSU_DIR}/uapi/supercall.h" 2>/dev/null || echo "")

if [ -n "$KSU_UAPI_VERSION" ]; then
    KSUNEXT_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE}/${KSU_UAPI_VERSION})"
else
    KSUNEXT_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE})"
fi
echo "KSUNEXT_VERSION_DISPLAY=${KSUNEXT_VERSION_DISPLAY}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "Version: ${KSUNEXT_VERSION_DISPLAY}"

# ======================================================
# 3. Kconfig
# ======================================================
# No CONFIG_KPM here — KernelPatch is a SukiSU-Ultra/ReSukiSU feature,
# KernelSU-Next's Kconfig doesn't declare it.

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIGS
fi
log "Configs enabled ✅"

log "KernelSU-Next ready ✅"
