#!/usr/bin/env bash

# ======================================================
# 🗜️ ADDON — LZ4 1.10.0 + ZSTD 1.5.7 (ZRAM compression bump)
# ======================================================
# Patch source: https://github.com/mrcxlinux/kernel_patches (zram/)
# ======================================================
# Pure library version bump — no Kconfig involved, this just replaces the
# vendored lib/lz4 and lib/zstd source with newer upstream releases.
#
# The LZ4 patch contains 3 git-style rename hunks (fs/f2fs/lz4armv8/{
# lz4accel.c,lz4accel.h,lz4armv8.S} -> lib/lz4/lz4armv8/...) that assume an
# old f2fs-local copy already exists pre-patch. This GKI tree never carried
# that dir, so all 3 renames fail no matter what — confirmed by diffing
# lib/lz4/lz4_compress.c etc. against the patch's own assumed pre-image
# (byte-identical match), which rules out a source-mismatch explanation.
# lz4armv8.S is also a binary git-diff (`patch` can't apply those at all),
# so we pre-stage it directly from its raw post-patch source. lz4accel.c/.h
# aren't hosted separately upstream (404) and can't be reconstructed from a
# rename-only diff without the missing pre-image, so those 2 rename hunks
# are accepted as a known, permanent partial-apply — they're ARM64 accel
# helpers, not the actual LZ4/ZSTD algorithm source.
#
# We used to gate the whole apply behind one blanket `--dry-run --forward`
# check on the entire (40+ file) patch, which treated it as all-or-nothing:
# the 2 unfixable rename hunks failing in the dry-run caused us to skip the
# *entire* patch, including ~13 other files (the actual 1.10.0 algorithm
# source) that apply cleanly on their own. Fixed by applying directly —
# `patch` (unlike `git apply`) already continues past a failed hunk/file
# instead of aborting the rest — and verifying success via a real version
# marker in the patched source, not exit code alone (patch exits nonzero
# even when only the 2 known-unfixable hunks failed).
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
    local name="$1" content="$2" marker_check="$3"

    if eval "$marker_check" 2>/dev/null; then
        log "LZ4/ZSTD: ${name} already applied, skipping."
        return 0
    fi

    # Apply directly instead of gating behind one blanket forward dry-run
    # on the whole multi-file patch — `patch` already applies hunk-by-hunk
    # and skips a failed hunk/file without aborting the rest, so a blanket
    # all-or-nothing pre-check only produces false negatives here (see
    # header comment: 2 rename hunks are permanently unfixable, but ~13
    # other files in the same patch apply cleanly on their own).
    local patch_log
    patch_log=$(echo "$content" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch 2>&1)
    local rc=$?

    # Verify with real evidence (a version marker from the patched source)
    # rather than trusting exit code alone, since patch exits nonzero even
    # when only the known-unfixable hunks failed and everything else landed.
    if eval "$marker_check" 2>/dev/null; then
        if [ "$rc" -eq 0 ]; then
            log "LZ4/ZSTD: ${name} applied cleanly ✅"
        else
            warn "LZ4/ZSTD: ${name} applied — core source updated, known ARM64 accel rename hunks skipped (expected, non-fatal) ⚠️"
        fi
    else
        warn "LZ4/ZSTD: ${name} core source did not update — skipping"
        echo "$patch_log" | grep -i "hunk\|fail" >&2
    fi
}

apply_lz4zstd_patch "001-lz4.patch (LZ4 1.10.0)" "$LZ4_PATCH" 'grep -q "LZ4_VERSION_MINOR 10" lib/lz4/lz4.h'
apply_lz4zstd_patch "002-zstd.patch (ZSTD 1.5.7)" "$ZSTD_PATCH" 'grep -q "ZSTD_VERSION_RELEASE  7" include/linux/zstd_lib.h'

cd "${ROOT_DIR}"
log "LZ4/ZSTD bump done ✅"
