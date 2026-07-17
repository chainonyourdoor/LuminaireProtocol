#!/usr/bin/env bash

# ======================================================
# 🔒 ADDON — WireGuard (kernel-level VPN)
# ======================================================
# Upstream: https://www.wireguard.com/
# ======================================================
# No patch needed — WireGuard has been in mainline Linux since 5.6,
# so drivers/net/wireguard/ is already present in this GKI tree. This is
# purely a Kconfig flip, same as any other config-only addon here.

GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_WIREGUARD=y" "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'CONFIGS'
# WireGuard (Luminaire)
CONFIG_WIREGUARD=y
CONFIGS
    log "WireGuard: CONFIG_WIREGUARD enabled ✅"
fi

log "WireGuard kernel-level VPN support enabled ✅"
