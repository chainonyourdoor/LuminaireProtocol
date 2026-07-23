#!/usr/bin/env bash

# ======================================================
# 🚀 ADDON — BBRv3
# TCP congestion control backport by fatalcoder524
# Patch source: https://github.com/WildKernels/kernel_patches
# ======================================================

BBRV3_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/common/bbrv3"

case "${KERNEL_VERSION}" in
    5.10) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android12-5.10.patch" ;;
    5.15) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android13-5.15.patch" ;;
    6.1)  BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android14-6.1.patch"  ;;
    6.6)  BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android15-6.6.patch"  ;;
    *)    error "BBRv3: unsupported kernel version '${KERNEL_VERSION}'" ;;
esac

log "🚀 Applying BBRv3 patch (${BBRV3_PATCH})..."
cd "${KERNEL_SRC}"

PATCH_CONTENT=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "${BBRV3_PATCHES_BASE}/${BBRV3_PATCH}") \
    || error "BBRv3: failed to download patch!"

[ -n "$PATCH_CONTENT" ] || error "BBRv3: downloaded patch is empty!"

if echo "$PATCH_CONTENT" | patch -p1 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
    log "BBRv3: patch already applied, skipping."
elif echo "$PATCH_CONTENT" | patch -p1 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
    echo "$PATCH_CONTENT" | patch -p1 --forward --no-backup-if-mismatch \
        || error "BBRv3: patch apply failed!"
    log "BBRv3: patch applied ✅"
else
    error "BBRv3: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "CONFIG_DEFAULT_BBR3" "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'EOF'
# BBRv3 as default TCP congestion (Luminaire)
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR3=y
CONFIG_DEFAULT_BBR3=y
EOF
    log "BBRv3: TCP_CONG_ADVANCED + DEFAULT_BBR3 injected into gki_defconfig ✅"
fi

if [ "${KERNEL_VERSION}" = "5.10" ]; then
    SYSCTL_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
        "${BBRV3_PATCHES_BASE}/sysctl_add_proc_dou8vec_minmax.patch") || true
    if [ -n "$SYSCTL_PATCH" ]; then
        if ! grep -qF 'int proc_dou8vec_minmax(' "${KERNEL_SRC}/include/linux/sysctl.h" 2>/dev/null; then
            echo "$SYSCTL_PATCH" | patch -p1 --forward --no-backup-if-mismatch || true
            SYSCTL_FIX=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
                "${BBRV3_PATCHES_BASE}/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch") || true
            [ -n "$SYSCTL_FIX" ] && echo "$SYSCTL_FIX" | patch -p1 --forward --no-backup-if-mismatch || true
        fi
    fi
fi

python3 "${LUMINAIRE_PATCH_DIR}/kernel/addons/bbrv3/enforcer.py" "${KERNEL_SRC}/net/ipv4/tcp_cong.c" \
    || error "BBRv3: enforcer injection into tcp_cong.c failed!"

cd "${ROOT_DIR}"

log "BBRv3 patch applied, default-congestion enforcer injected ✅"
