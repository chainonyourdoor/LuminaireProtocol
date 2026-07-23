#!/usr/bin/env bash

GLIBC_VERSION="$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
if [ "$(printf '%s\n' "2.38" "$GLIBC_VERSION" | sort -V | head -n 1)" = "2.38" ]; then
    log "Applying GLIBC >= 2.38 fix..."
    BTFIDS_MK="${KERNEL_SRC}/tools/bpf/resolve_btfids/Makefile"

    if [ ! -f "$BTFIDS_MK" ]; then
        warn "GLIBC fix: resolve_btfids/Makefile not found — skipping"
    else
        OLD_PATTERN='$(Q)$(MAKE) -C $(SUBCMD_SRC) OUTPUT=$(abspath $(dir $@))/ $(abspath $@)'

        if grep -qF "$OLD_PATTERN" "$BTFIDS_MK"; then
            sed -i 's/$(Q)$(MAKE) -C $(SUBCMD_SRC) OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/$(Q)$(MAKE) -C $(SUBCMD_SRC) EXTRA_CFLAGS="$(CFLAGS)" OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/' \
                "$BTFIDS_MK"
            log "GLIBC fix applied ✅"
        elif grep -qF 'EXTRA_CFLAGS="$(CFLAGS)"' "$BTFIDS_MK"; then
            log "GLIBC fix already applied, skipping ✅"
        elif grep -qF 'HOST_OVERRIDES' "$BTFIDS_MK" && grep -qF 'EXTRA_CFLAGS=' "$BTFIDS_MK"; then
            log "GLIBC fix not needed — upstream Makefile already passes EXTRA_CFLAGS via HOST_OVERRIDES ✅"
        else
            warn "GLIBC fix: unrecognized resolve_btfids/Makefile structure — skipping (manual review may be needed)"
        fi
    fi
else
    log "GLIBC < 2.38 detected, fix not needed ✅"
fi
