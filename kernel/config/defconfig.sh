#!/usr/bin/env bash

config() {
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" "$@"
}

log "Merging luminaire.fragment..."
"${KERNEL_SRC}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
    "${OUT_DIR}/.config" \
    "${LUMINAIRE_PATCH_DIR}/kernel/config/luminaire.fragment"
log "Fragment merged ✅"

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
    [ "${LTO_MODE}" = "NONE" ] \
        || warn "Unknown LTO_MODE value '${LTO_MODE}', defaulting to NONE"
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
fi

log "Luminaire defconfig applied ✅"

if [ "${LZ4KD_ENABLED:-false}" = "true" ]; then
    config --enable CONFIG_CRYPTO_LZ4HC
    config --enable CONFIG_CRYPTO_LZ4K
    config --enable CONFIG_CRYPTO_LZ4KD
    config --enable CONFIG_LZ4K_COMPRESS
    config --enable CONFIG_LZ4K_DECOMPRESS
    config --enable CONFIG_LZ4KD_COMPRESS
    config --enable CONFIG_LZ4KD_DECOMPRESS
    config --enable CONFIG_ZRAM
    config --disable CONFIG_ZRAM_DEF_COMP_LZ4
    config --enable CONFIG_ZRAM_DEF_COMP_LZ4KD
    LZ4KD_STATE=$(config --state CONFIG_CRYPTO_LZ4KD 2>/dev/null || echo "unknown")
    ZRAM_STATE=$(config --state CONFIG_ZRAM 2>/dev/null || echo "unknown")
    ZRAM_DEF_STATE=$(config --state CONFIG_ZRAM_DEF_COMP_LZ4KD 2>/dev/null || echo "unknown")
    log "LZ4KD: CONFIG_CRYPTO_LZ4KD state after scripts/config --enable: ${LZ4KD_STATE}"
    log "LZ4KD: CONFIG_ZRAM state after scripts/config --enable (should be 'y', not 'm'): ${ZRAM_STATE}"
    log "LZ4KD: CONFIG_ZRAM_DEF_COMP_LZ4KD state after scripts/config --enable: ${ZRAM_DEF_STATE}"
fi

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
