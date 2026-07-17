#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Kernel Config
# Applied after gki_defconfig via scripts/config
# ======================================================

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
if [ "${LTO_MODE}" = "THIN" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --enable  CONFIG_LTO_CLANG_THIN
    log "LTO: THIN ✅"
elif [ "${LTO_MODE}" = "FULL" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    config --enable  CONFIG_LTO_CLANG_FULL
    log "LTO: FULL ✅"
else
    # Covers both the explicit "NONE" value and any unrecognized value —
    # NONE is the safe fallback either way, only the log line differs.
    [ "${LTO_MODE}" = "NONE" ] \
        || warn "Unknown LTO_MODE value '${LTO_MODE}', defaulting to NONE"
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
fi

log "Luminaire defconfig applied ✅"

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
