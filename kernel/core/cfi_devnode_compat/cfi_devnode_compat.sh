#!/usr/bin/env bash

BASE_MK="${KERNEL_SRC}/drivers/base/Makefile"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/cfi_devnode_compat/patch.py"

[ -f "$BASE_MK" ] || { warn "drivers/base/Makefile not found, skipping cfi_devnode_compat"; return 0; }

grep -q "CFLAGS_trace.o" "$BASE_MK" \
    || { warn "CFLAGS_trace.o anchor not found — drivers/base/Makefile shape changed, skipping cfi_devnode_compat"; return 0; }

python3 "$PATCHER" "$BASE_MK" \
    || error "cfi_devnode_compat: patch script failed!"

log "cfi_devnode_compat applied ✅"
