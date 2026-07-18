#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — LZ4KD (ZRAM compression optimization)
# ======================================================
# Source: https://github.com/SukiSU-Ultra/SukiSU_patch (other/zram/)
# ======================================================
# Adds the lz4k/lz4kd compressor backends for zram (kernel-delta-aware
# variants of LZ4) plus the Kconfig/Makefile/zcomp.c wiring to register
# them. Version-keyed by upstream per kernel branch — this repo only
# targets android14-6.1-lts, so only that one path is used below; add a
# case statement here if a second kernel version is ever supported.

LZ4KD_RAW_BASE="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/main/other/zram"
cd "${KERNEL_SRC}"

log "Downloading LZ4KD source files..."
LZ4KD_FILES=(
    "include/linux/lz4k.h"
    "include/linux/lz4kd.h"
    "lib/lz4k/Makefile"
    "lib/lz4k/lz4k_decode.c"
    "lib/lz4k/lz4k_encode.c"
    "lib/lz4k/lz4k_encode_private.h"
    "lib/lz4k/lz4k_private.h"
    "lib/lz4kd/Makefile"
    "lib/lz4kd/lz4kd_decode.c"
    "lib/lz4kd/lz4kd_decode_delta.c"
    "lib/lz4kd/lz4kd_encode.c"
    "lib/lz4kd/lz4kd_encode_delta.c"
    "lib/lz4kd/lz4kd_encode_private.h"
    "lib/lz4kd/lz4kd_private.h"
    "crypto/lz4k.c"
    "crypto/lz4kd.c"
)
for f in "${LZ4KD_FILES[@]}"; do
    mkdir -p "$(dirname "$f")"
    curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
        -o "$f" "${LZ4KD_RAW_BASE}/lz4k/${f}" \
        || error "LZ4KD: failed to download ${f}!"
done
log "LZ4KD source files staged ✅"

LZ4KD_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "${LZ4KD_RAW_BASE}/zram_patch/6.1/lz4kd.patch") \
    || error "LZ4KD: failed to download lz4kd.patch!"
[ -n "$LZ4KD_PATCH" ] || error "LZ4KD: downloaded patch is empty!"

if echo "$LZ4KD_PATCH" | patch -p1 --fuzz=3 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
    log "LZ4KD: patch already applied, skipping."
elif echo "$LZ4KD_PATCH" | patch -p1 --fuzz=3 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
    echo "$LZ4KD_PATCH" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch \
        || error "LZ4KD: patch apply failed!"
    log "LZ4KD: patch applied ✅"
else
    error "LZ4KD: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_CRYPTO_LZ4KD=y" "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'CONFIGS'
# LZ4KD (Luminaire)
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIGS
    log "LZ4KD: configs enabled ✅"
fi
export LZ4KD_ENABLED=true

cd "${ROOT_DIR}"
log "LZ4KD ZRAM optimization integrated ✅"
