#!/usr/bin/env bash

# Addon — Droidspaces (LXC container runtime). See CODEX.md for the
# KaBI-patch-per-kernel-version selection logic and 5.10 note.

log "Enabling Droidspaces support..."

case "${KERNEL_VERSION}" in
    5.10|5.15|6.1|6.6|6.6-konoha) KABI_PATCH_NAME="001_GKI-below-6_12-fix_sysvipc_kabi_6_7_8.patch" ;;
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
# Per-config idempotent check — some kernel sources (e.g. 6.1 after the
# upstream catch-up merge) may already carry a subset of these in
# gki_defconfig directly. A single-flag guard (checking only one config)
# would either skip the whole block once that one config is already present
# — silently leaving the rest missing — or duplicate entries that are
# already there. Checking each config individually avoids both.
GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
DROIDSPACES_CONFIGS=(
    CONFIG_SYSVIPC
    CONFIG_PID_NS
    CONFIG_IPC_NS
    CONFIG_UTS_NS
    CONFIG_DEVTMPFS
    CONFIG_CGROUP_DEVICE
    CONFIG_NET_NS
    CONFIG_NETFILTER_XT_TARGET_LOG
    CONFIG_NETFILTER_XT_MATCH_RECENT
    CONFIG_BINFMT_ELF
    CONFIG_BINFMT_SCRIPT
)
MISSING_CONFIGS=()
for cfg in "${DROIDSPACES_CONFIGS[@]}"; do
    grep -q "^${cfg}=y" "$GKI_DEFCONFIG" || MISSING_CONFIGS+=("${cfg}=y")
done
if [ "${#MISSING_CONFIGS[@]}" -gt 0 ]; then
    {
        echo ""
        echo "# Droidspaces — added by addon (missing from base defconfig)"
        printf '%s\n' "${MISSING_CONFIGS[@]}"
    } >> "$GKI_DEFCONFIG"
    log "Droidspaces: added ${#MISSING_CONFIGS[@]} missing config(s): ${MISSING_CONFIGS[*]}"
else
    log "Droidspaces: all required configs already present"
fi
log "Droidspaces configs enabled ✅"
