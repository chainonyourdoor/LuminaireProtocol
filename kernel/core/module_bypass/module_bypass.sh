#!/usr/bin/env bash

if [ "${MODULE_BYPASS_ENABLED:-true}" != "true" ]; then
    log "Module version bypass disabled (MODULE_BYPASS_ENABLED=false) — skipping"
    return 0
fi

MODULE_VERSION_FILE="${KERNEL_SRC}/kernel/module/version.c"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/module_bypass/patch.py"

if [ -f "$MODULE_VERSION_FILE" ]; then
    python3 "$PATCHER" "$MODULE_VERSION_FILE" \
        || error "Module version bypass: patch script failed!"
    log "Module version bypass applied ✅"
fi
