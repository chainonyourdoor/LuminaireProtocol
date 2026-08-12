#!/usr/bin/env bash

CORE_C="${KERNEL_SRC}/drivers/base/core.c"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/cfi_devnode_compat/patch.py"

[ -f "$CORE_C" ] || { warn "drivers/base/core.c not found, skipping cfi_devnode_compat"; return 0; }

python3 "$PATCHER" "$CORE_C" \
    || error "cfi_devnode_compat: patch script failed!"

log "cfi_devnode_compat applied ✅"
