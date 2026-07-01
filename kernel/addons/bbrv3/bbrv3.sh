#!/usr/bin/env bash

# ======================================================
# 🚀 ADDON — BBRv3
# TCP congestion control patch from WildKernels/kernel_patches
# Sets BBRv3 as the default TCP congestion algorithm
# ======================================================

BBRV3_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/bbr"

# Map kernel version to patch filename
case "${KERNEL_VERSION}" in
    5.10) BBRV3_PATCH="bbrv3-android12-5.10.patch" ;;
    5.15)
        case "${ANDROID_VERSION:-android13}" in
            android13) BBRV3_PATCH="bbrv3-android13-5.15.patch" ;;
            *)         BBRV3_PATCH="bbrv3-android14-5.15.patch" ;;
        esac
        ;;
    6.1)  BBRV3_PATCH="bbrv3-android14-6.1.patch"  ;;
    6.6)  BBRV3_PATCH="bbrv3-android15-6.6.patch"  ;;
    6.12) BBRV3_PATCH="bbrv3-android16-6.12.patch" ;;
    *)
        error "BBRv3: unsupported kernel version '${KERNEL_VERSION}'"
        ;;
esac

PATCH_URL="${BBRV3_PATCHES_BASE}/${BBRV3_PATCH}"

log "🚀 Applying BBRv3 patch (${BBRV3_PATCH})..."
cd "${KERNEL_SRC}"

PATCH_CONTENT=$(curl -LSs --fail --retry 3 --connect-timeout 30 "${PATCH_URL}") \
    || error "BBRv3: failed to download patch from ${PATCH_URL}"

[ -n "$PATCH_CONTENT" ] || error "BBRv3: downloaded patch is empty!"

echo "$PATCH_CONTENT" | patch -p1 --forward --no-backup-if-mismatch \
    || error "BBRv3: patch apply failed!"

# Set BBRv3 as default TCP congestion control in defconfig
DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"

log "Configuring BBRv3 as default TCP congestion control..."

for config in \
    "CONFIG_TCP_CONG_BBR=y" \
    "CONFIG_DEFAULT_TCP_CONG=\"bbr\"" \
    "CONFIG_NET_SCH_FQ=y"; do
    key="${config%%=*}"
    if grep -q "^${key}=" "${DEFCONFIG_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${config}|" "${DEFCONFIG_FILE}"
    else
        echo "${config}" >> "${DEFCONFIG_FILE}"
    fi
done

cd "${ROOT_DIR}"

export BBRV3_ENABLED=true

log "BBRv3 setup complete ✅"
