#!/usr/bin/env bash

# ======================================================
# 🗜️ ADDON — LZ4 1.10.0 + ZSTD 1.5.7 (ZRAM compression bump)
# ======================================================
# Patch source: https://github.com/mrcxlinux/kernel_patches (zram/)
# ======================================================
# Pure library version bump — no Kconfig involved, this just replaces the
# vendored lib/lz4 and lib/zstd source with newer upstream releases.
#
# The LZ4 patch contains one git-style rename hunk (fs/f2fs/lz4armv8/
# lz4accel.c -> lib/lz4/lz4armv8/lz4accel.c) that assumes the old f2fs-local
# copy already exists pre-patch. This GKI tree doesn't carry that file, so
# we pre-stage lz4armv8.S at its post-patch destination ourselves (same
# workaround the patch's own upstream CI uses) and apply with `patch`
# (not `git apply`) so a failed rename hunk can't abort the rest of the
# patch — the surrounding hunks (lib/lz4/lz4.c, crypto/lz4.c, etc., the
# actual 1.10.0 source) are independent of it.
#
# Non-fatal on failure (warn, not error): this is a compression-ratio/
# speed optimization, not a correctness-critical patch — a build without
# it just keeps whatever LZ4/ZSTD version this kernel branch already ships.

LZ4ZSTD_PATCH_BASE="https://raw.githubusercontent.com/mrcxlinux/kernel_patches/main/zram"
cd "${KERNEL_SRC}"

log "Downloading LZ4/ZSTD patches..."
LZ4_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 "${LZ4ZSTD_PATCH_BASE}/001-lz4.patch") \
    || { warn "LZ4/ZSTD: failed to download 001-lz4.patch — skipping"; return 0; }
ZSTD_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 "${LZ4ZSTD_PATCH_BASE}/002-zstd.patch") \
    || { warn "LZ4/ZSTD: failed to download 002-zstd.patch — skipping"; return 0; }
curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 -o /tmp/lz4armv8.S "${LZ4ZSTD_PATCH_BASE}/lz4armv8.S" \
    || { warn "LZ4/ZSTD: failed to download lz4armv8.S — skipping"; return 0; }

[ -n "$LZ4_PATCH" ] && [ -n "$ZSTD_PATCH" ] || { warn "LZ4/ZSTD: a downloaded patch is empty — skipping"; return 0; }

# Pre-stage the arm64 accel source at its post-patch location (see comment
# above) so the LZ4 patch's own rename hunk failing doesn't cost us the
# actual asm file.
mkdir -p lib/lz4/lz4armv8
cp /tmp/lz4armv8.S lib/lz4/lz4armv8/lz4armv8.S

apply_lz4zstd_patch() {
    local name="$1" content="$2"
    if echo "$content" | patch -p1 --fuzz=3 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
        log "LZ4/ZSTD: ${name} already applied, skipping."
    elif echo "$content" | patch -p1 --fuzz=3 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
        echo "$content" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch \
            && log "LZ4/ZSTD: ${name} applied ✅" \
            || warn "LZ4/ZSTD: ${name} apply reported errors (see log) — some hunks may have been skipped"
    else
        warn "LZ4/ZSTD: ${name} does not apply cleanly (even partially) — skipping"
    fi
}

apply_lz4zstd_patch "001-lz4.patch (LZ4 1.10.0)" "$LZ4_PATCH"
apply_lz4zstd_patch "002-zstd.patch (ZSTD 1.5.7)" "$ZSTD_PATCH"

cd "${ROOT_DIR}"
log "LZ4/ZSTD bump done ✅"
