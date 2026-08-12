#!/usr/bin/env bash

VMSCAN_C="${KERNEL_SRC}/mm/vmscan.c"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/mglru_force_enable/patch.py"

[ -f "$VMSCAN_C" ] || { warn "mm/vmscan.c not found, skipping mglru_force_enable"; return 0; }

grep -q "^static ssize_t store_enabled(struct kobject \*kobj," "$VMSCAN_C" \
    || { warn "store_enabled() not found in this kernel's shape — MGLRU doesn't exist here or its shape changed, skipping"; return 0; }

python3 "$PATCHER" "$VMSCAN_C" \
    || error "mglru_force_enable: patch script failed!"

log "mglru_force_enable applied ✅"
