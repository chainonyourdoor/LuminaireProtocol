#!/usr/bin/env bash

# ======================================================
# 🔤 COMPILER STRING — SANITIZE UTS VERSION
# ======================================================

MKCOMPILE_H="${KERNEL_SRC}/scripts/mkcompile_h"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/compiler_string/patch.py"

[ -f "$MKCOMPILE_H" ] || { warn "mkcompile_h not found, skipping compiler string patch"; return 0; }

python3 "$PATCHER" "$MKCOMPILE_H" "$COMPILER_STRING" \
    || error "Compiler string patch failed!"

log "Compiler string patched in mkcompile_h ✅"
