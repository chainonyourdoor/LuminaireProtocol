#!/usr/bin/env bash

log "Setting up Baseband Guard (BBG)..."
cd "${KERNEL_SRC}"
BBG_SETUP=$(wget --no-verbose -O- --timeout=30 --tries=3 \
    "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh") \
    || error "BBG: failed to download setup.sh!"
[ -n "$BBG_SETUP" ] || error "BBG: setup.sh is empty!"
echo "$BBG_SETUP" | grep -q "^#!" || error "BBG: setup.sh looks invalid (no shebang)!"
echo "$BBG_SETUP" | bash || error "BBG: setup.sh failed!"
[ -L "${KERNEL_SRC}/security/baseband-guard" ] \
    || error "BBG: inject failed — security/baseband-guard symlink not found!"
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' \
    "${KERNEL_SRC}/security/Kconfig"
cd "${ROOT_DIR}"

log "Enabling CONFIG_BBG..."
if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
    echo "CONFIG_BBG=y" >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
else
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" --enable CONFIG_BBG
fi
log "BBG setup complete ✅"
