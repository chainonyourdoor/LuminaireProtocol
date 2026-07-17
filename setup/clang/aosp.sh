#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — AOSP (mirrored by bachnxuan/aosp_clang_mirror)
# ======================================================

log "Downloading AOSP Clang..."

AOSP_URL=$(curl -fsSL https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((x['browser_download_url'] for x in d.get('assets',[]) if x['name'].endswith('.tar.gz')), ''))") \
    || error "AOSP: failed to query GitHub API!"
[ -n "$AOSP_URL" ] || error "AOSP: no .tar.gz asset found in latest release!"

retry 3 run_quiet curl -fL "$AOSP_URL" -o /tmp/clang.tar.gz \
    || error "AOSP: download failed!"

# Unlike the other variants, this mirror's tarball has no wrapping top-level
# directory — bin/, lib64/, etc. already sit at archive root (it's a direct
# repack of the AOSP prebuilt tree), so no --strip-components here.
tar -xf /tmp/clang.tar.gz -C "$TOOL_CLANG_DIR"
rm -f /tmp/clang.tar.gz
log "AOSP Clang downloaded ✅"
