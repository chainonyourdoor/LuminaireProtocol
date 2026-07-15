#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — IPSet
# ======================================================
# Native upstream Kconfig option — no external repo/patch, just turns on
# IP_SET + common set types in gki_defconfig. Needed by firewall / ad-block
# apps that build on ipset(8) plus the iptables "set" match/target
# (NetGuard, AFWall+, and similar).

log "Enabling IPSet support..."

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_IP_SET=y" "$DEFCONFIG_FILE"; then
    cat >> "$DEFCONFIG_FILE" << 'EOF'
# IPSet support (Luminaire)
CONFIG_IP_SET=y
CONFIG_IP_SET_MAX=256
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_LIST_SET=y
CONFIG_NETFILTER_XT_SET=y
EOF
    log "IPSet: CONFIG_IP_SET + common set types enabled ✅"
fi

log "IPSet support integrated ✅"
