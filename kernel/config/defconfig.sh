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

# LZ4KD: same class of bug as CONFIG_SCHED_BORE (see bore.sh/defconfig.sh
# history) — gki_defconfig text-append alone isn't reliably surviving to
# the final compiled kernel. On-device verification showed crypto/lz4k.o
# and crypto/lz4kd.o both compile and register in /proc/crypto (so the
# Kconfig symbol, Makefile obj-y line, and patch apply are all correct at
# patch-apply time), yet CONFIG_CRYPTO_LZ4K/LZ4KD are absent from
# /proc/config.gz on the flashed device and zcomp.c's
# IS_ENABLED(CONFIG_CRYPTO_LZ4K) backend-list guard evaluates false, so
# zram never offers "lz4k"/"lz4kd" as a comp_algorithm option. Root cause
# not pinned down (same as BORE). Enforcing here too, directly on the
# post-merge .config via scripts/config (same proven mechanism as
# LTO_MODE/BBG above) as a second, more direct path. The LZ4K_*/LZ4KD_*
# symbols are plain `tristate` (select-only, no prompt) in lib/Kconfig —
# scripts/config bypasses Kconfig's `select` resolution entirely, so they
# need to be forced explicitly too, not just the crypto/Kconfig-level
# CRYPTO_LZ4K/LZ4KD symbols that normally `select` them.
if [ "${LZ4KD_ENABLED:-false}" = "true" ]; then
    config --enable CONFIG_CRYPTO_LZ4HC
    config --enable CONFIG_CRYPTO_LZ4K
    config --enable CONFIG_CRYPTO_LZ4KD
    config --enable CONFIG_LZ4K_COMPRESS
    config --enable CONFIG_LZ4K_DECOMPRESS
    config --enable CONFIG_LZ4KD_COMPRESS
    config --enable CONFIG_LZ4KD_DECOMPRESS
    LZ4KD_STATE=$(config --state CONFIG_CRYPTO_LZ4KD 2>/dev/null || echo "unknown")
    log "LZ4KD: CONFIG_CRYPTO_LZ4KD state after scripts/config --enable: ${LZ4KD_STATE}"
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
