#!/usr/bin/env bash

# ======================================================
# 🔐 OPENSSL 3 COMPAT — certs/extract-cert.c
# ======================================================
# certs/extract-cert.c ships from upstream with a half-applied backport of
# the OpenSSL-3 compat fix: it gates key_pass's declaration behind
# `#ifdef USE_PKCS11_ENGINE`, but never defines that macro anywhere in the
# file, and the PKCS#11 branch further down uses key_pass completely
# unguarded. Result: "error: use of undeclared identifier 'key_pass'" on
# any OpenSSL 3.x toolchain (every current GitHub Actions runner) — breaks
# every build regardless of addons/root solution/build system.
#
# See patch.py for the actual fix (defines the missing macro).

EXTRACT_CERT="${KERNEL_SRC}/certs/extract-cert.c"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/openssl3_compat/patch.py"

[ -f "$EXTRACT_CERT" ] || { warn "extract-cert.c not found, skipping OpenSSL 3 compat patch"; return 0; }

python3 "$PATCHER" "$EXTRACT_CERT" \
    || error "OpenSSL 3 compat patch failed!"

log "OpenSSL 3 compat patched in extract-cert.c ✅"
