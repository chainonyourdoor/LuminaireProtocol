#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Kernel Config
# Applied after gki_defconfig via scripts/config
# ======================================================

[ "$BUILD_SYSTEM" = "KLEAF" ] && return 0

config() {
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" "$@"
}

# Merge Luminaire fragment
log "Merging luminaire.fragment..."
"${KERNEL_SRC}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
    "${OUT_DIR}/.config" \
    "${LUMINAIRE_PATCH_DIR}/kernel/config/luminaire.fragment"
log "Fragment merged ✅"

# LTO
if [ "${ENABLE_LTO}" = "THIN" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --enable  CONFIG_LTO_CLANG_THIN
    log "LTO: THIN ✅"
elif [ "${ENABLE_LTO}" = "FULL" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    config --enable  CONFIG_LTO_CLANG_FULL
    log "LTO: FULL ✅"
elif [ "${ENABLE_LTO}" = "NONE" ]; then
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
else
    warn "Unknown ENABLE_LTO value '${ENABLE_LTO}', defaulting to NONE"
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
fi

log "Luminaire defconfig applied ✅"

# BBRv3 — set as default TCP congestion control
if [ "${BBRV3_ENABLED:-false}" = "true" ]; then
    config --enable  CONFIG_TCP_CONG_BBR
    config --enable  CONFIG_NET_SCH_FQ
    config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"
    log "BBRv3: TCP congestion set to bbr ✅"
fi

# BBG requires baseband_guard in CONFIG_LSM — patch here because .config
# is not available when bbg.sh runs (before make defconfig)
if [ "${BBG_ENABLED:-false}" = "true" ]; then
    CURRENT_LSM=$(config --state CONFIG_LSM 2>/dev/null | tr -d '"' || true)
    if [ -z "$CURRENT_LSM" ] || [ "$CURRENT_LSM" = "undef" ]; then
        warn "BBG: CONFIG_LSM state unknown — skipping LSM patch"
    elif echo "$CURRENT_LSM" | grep -q "baseband_guard"; then
        log "BBG: baseband_guard already in CONFIG_LSM ✅"
    else
        config --set-str CONFIG_LSM "${CURRENT_LSM},baseband_guard"
        log "BBG: baseband_guard appended to CONFIG_LSM ✅"
    fi
fi
