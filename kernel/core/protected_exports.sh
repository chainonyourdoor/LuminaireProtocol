#!/usr/bin/env bash

# ======================================================
# 🗑️ REMOVE PROTECTED EXPORTS
# ======================================================

rm -rf "${KERNEL_SRC}/android/abi_gki_protected_exports_"*

log "Protected exports removed ✅"
