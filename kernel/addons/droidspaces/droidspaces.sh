#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Droidspaces (LXC container runtime)
# ======================================================
# Requires a KaBI-safety patch under kernel/patches/<android-ver>/required/
# (version-selected below — see Droidspaces-OSS's Kernel-Configuration.md)
# Docs: https://github.com/ravindu644/Droidspaces-OSS

log "Enabling Droidspaces support..."

# Which KaBI-safety patch applies depends on kernel version (per
# upstream ravindu644/Droidspaces-OSS Documentation/Kernel-Configuration.md):
#   - Below 6.12 (5.10/5.15/6.1/6.6): 001_GKI-below-6_12-fix_sysvipc_kabi_6_7_8.patch
#     (verified byte-identical to upstream's recommended variant)
#   - 6.12 and above: a different patch (task_struct layout fix differs)
# Kernel 5.10 ALSO needs an extra POSIX_MQUEUE padding patch — that one
# isn't referenced here explicitly, it's picked up automatically by
# build/make.sh's generic "${PATCHES_DIR}/required/*.patch" loop since
# it lives in the same directory (kernel/patches/android12-5.10/required/).
case "${KERNEL_VERSION}" in
    5.10|5.15|6.1|6.6) KABI_PATCH_NAME="001_GKI-below-6_12-fix_sysvipc_kabi_6_7_8.patch" ;;
    6.12)              KABI_PATCH_NAME="001_GKI-6.12-or-above-fix_sysvipc_kabi.patch" ;;
    *)                 error "Droidspaces: no known KaBI-safety patch for kernel ${KERNEL_VERSION} yet — this addon should have been gated out before reaching here (check registry.sh's ADDON_SUPPORTED_VERSIONS)." ;;
esac
KABI_PATCH="${PATCHES_DIR}/required/${KABI_PATCH_NAME}"
if [ ! -f "$KABI_PATCH" ]; then
    warn "Droidspaces: KaBI patch not found at ${KABI_PATCH} — SYSVIPC may cause KaBI violations on some devices"
elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KABI_PATCH" > /dev/null 2>&1; then
    log "Droidspaces: KaBI patch already applied ✅"
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$KABI_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 -d "$KERNEL_SRC" < "$KABI_PATCH" \
        || error "Droidspaces: KaBI patch failed — aborting to prevent KaBI violations!"
    log "Droidspaces: KaBI patch applied ✅"
else
    warn "Droidspaces: KaBI patch does not apply cleanly — skipping, KaBI violations possible"
fi
if ! grep -q "^CONFIG_SYSVIPC=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
# Droidspaces — Mandatory
CONFIG_SYSVIPC=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_UTS_NS=y
CONFIG_DEVTMPFS=y
CONFIG_CGROUP_DEVICE=y

# Droidspaces — Networking (NAT mode)
CONFIG_NET_NS=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y

# Droidspaces — Binfmt
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIGS
fi
log "Droidspaces configs enabled ✅"
