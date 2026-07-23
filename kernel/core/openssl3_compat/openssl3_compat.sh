#!/usr/bin/env bash

EXTRACT_CERT="${KERNEL_SRC}/certs/extract-cert.c"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/openssl3_compat/patch.py"

[ -f "$EXTRACT_CERT" ] || { warn "extract-cert.c not found, skipping OpenSSL 3 compat patch"; return 0; }

python3 "$PATCHER" "$EXTRACT_CERT" \
    || error "OpenSSL 3 compat patch failed!"

log "OpenSSL 3 compat patched in extract-cert.c ✅"
