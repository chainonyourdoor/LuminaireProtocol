#!/usr/bin/env bash

# ======================================================
# 🗑️ REMOVE PROTECTED EXPORTS
# ======================================================

rm -rf "${KERNEL_DIR}/common/android/abi_gki_protected_exports_"*

perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' \
    "${KERNEL_DIR}/common/BUILD.bazel" 2>/dev/null || true

sed -i 's/protected_modules = \[.*\]/protected_modules = []/' \
    "${KERNEL_DIR}/common/modules.bzl" 2>/dev/null || true

log "Protected exports removed ✅"
