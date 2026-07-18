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
#
# CONFIG_ZRAM=m by default (stock gki_defconfig) — zram then ships as a
# separate zram.ko, loaded on this device from the read-only,
# dm-verity-protected system_dlkm partition (confirmed via `cat
# /proc/mounts`), not the boot ramdisk. AnyKernel3's repack flow only
# touches boot.img, so a rebuilt zram.ko with LZ4K/LZ4KD support never
# reaches the running device no matter how correct the compile is — the
# stock system_dlkm zram.ko keeps loading every boot. Forcing =y here
# builds zram directly into Image instead (same as WireGuard/lib/zstd),
# which *does* ship via the normal AK3 flash — same fix other SM8750 GKI
# kernel builders (e.g. ox1d3x3/Op13_Susfs_kernel) use for this exact
# reason. Only touch this when LZ4KD is actually enabled — no reason to
# change zram's module-ness on builds that don't need it.
if [ "${LZ4KD_ENABLED:-false}" = "true" ]; then
    config --enable CONFIG_CRYPTO_LZ4HC
    config --enable CONFIG_CRYPTO_LZ4K
    config --enable CONFIG_CRYPTO_LZ4KD
    config --enable CONFIG_LZ4K_COMPRESS
    config --enable CONFIG_LZ4K_DECOMPRESS
    config --enable CONFIG_LZ4KD_COMPRESS
    config --enable CONFIG_LZ4KD_DECOMPRESS
    config --enable CONFIG_ZRAM
    # The lz4kd.patch itself already flips the ZRAM_DEF_COMP choice's
    # default from ZRAM_DEF_COMP_LZORLE to ZRAM_DEF_COMP_LZ4KD (so lz4kd
    # becomes the kernel's own boot-time default, zero userspace steps
    # needed) — but luminaire.fragment unconditionally forces
    # ZRAM_DEF_COMP_LZ4=y earlier in this same script for builds that
    # don't have LZ4KD, which otherwise silently overrides the patch's
    # intent here too. Force it back to LZ4KD explicitly so it doesn't
    # require a manual `echo lz4kd > comp_algorithm` after every boot.
    # scripts/config edits .config as flat text — it has no notion of
    # Kconfig `choice` groups, so --enable on one choice member does NOT
    # automatically clear sibling members the way real Kconfig evaluation
    # would. luminaire.fragment already set ZRAM_DEF_COMP_LZ4=y earlier in
    # this script; without explicitly disabling it here too, both ended
    # up =y simultaneously and LZ4 (set first) kept winning on-device.
    config --disable CONFIG_ZRAM_DEF_COMP_LZ4
    config --enable CONFIG_ZRAM_DEF_COMP_LZ4KD
    LZ4KD_STATE=$(config --state CONFIG_CRYPTO_LZ4KD 2>/dev/null || echo "unknown")
    ZRAM_STATE=$(config --state CONFIG_ZRAM 2>/dev/null || echo "unknown")
    ZRAM_DEF_STATE=$(config --state CONFIG_ZRAM_DEF_COMP_LZ4KD 2>/dev/null || echo "unknown")
    log "LZ4KD: CONFIG_CRYPTO_LZ4KD state after scripts/config --enable: ${LZ4KD_STATE}"
    log "LZ4KD: CONFIG_ZRAM state after scripts/config --enable (should be 'y', not 'm'): ${ZRAM_STATE}"
    log "LZ4KD: CONFIG_ZRAM_DEF_COMP_LZ4KD state after scripts/config --enable: ${ZRAM_DEF_STATE}"
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
