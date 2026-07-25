#!/usr/bin/env bash

declare -A ADDON_SUPPORTED_VERSIONS=(
    # rekernel: EXPERIMENTAL widen (5.10/5.15/6.6/6.12 untested) — inject.py
    # was built/verified against android14-6.1 specifically (see docs/CODEX.md).
    # Its multi-anchor fallback in binder.c/binder_alloc.c/signal.c gives some
    # cross-tree robustness, but that's not the same as verified compat with
    # other kernel versions' source layout. Kept because inject.py hard-fails
    # (sys.exit(1) -> build error) if no anchor matches, so a bad version just
    # fails CI loudly instead of shipping a silently-broken kernel. If a
    # version in this list turns out to fail in CI, remove that version here.
    [rekernel]="5.10 5.15 6.1 6.6 6.12"
    [bbrv3]="5.10 5.15 6.1 6.6"
    [bbg]="5.10 5.15 6.1 6.6 6.12"
    [droidspaces]="5.10 5.15 6.1 6.6 6.12"
    [ntsync]="5.10 5.15 6.1 6.6 6.12"
    [wireguard]="5.10 5.15 6.1 6.6 6.12"
    [lz4zstd]="6.1"
    [lz4kd]="5.10 5.15 6.1 6.6"
    [kasumi]="5.10 5.15 6.1 6.6 6.12"
    [nomount]="5.10 5.15 6.1 6.6 6.12"
    [zeromount]="5.10 5.15 6.1 6.6 6.12"
)

ADDON_ORDER=(rekernel bbrv3 bbg droidspaces ntsync wireguard lz4zstd lz4kd kasumi nomount zeromount)

ADDON_MOUNTLESS_TOKENS=(nomount zeromount)

addon_supports_kernel_version() {
    local addon="$1"
    local supported="${ADDON_SUPPORTED_VERSIONS[$addon]:-}"
    [ -z "$supported" ] && return 1
    [[ " ${supported} " == *" ${KERNEL_VERSION} "* ]]
}

run_addons() {
    IFS=, ; ADDON_ORDER_STR="${ADDON_ORDER[*]}"; ADDON_MOUNTLESS_TOKENS_STR="${ADDON_MOUNTLESS_TOKENS[*]}"; unset IFS
    unset ADDON_ORDER ADDON_MOUNTLESS_TOKENS
    export ADDON_ORDER="${ADDON_ORDER_STR}" ADDON_MOUNTLESS_TOKENS="${ADDON_MOUNTLESS_TOKENS_STR}"
    echo "ADDON_ORDER=${ADDON_ORDER_STR}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "ADDON_MOUNTLESS_TOKENS=${ADDON_MOUNTLESS_TOKENS_STR}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    [ -z "${ADDONS:-}" ] && return 0
    ADDONS="${ADDONS// /}"
    ADDONS="$(echo "$ADDONS" | sed 's/^,*//;s/,*$//;s/,,*/,/g')"
    [ -z "${ADDONS}" ] && return 0
    echo "::group::⚡ Addons"
    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"

    if [[ ",${ADDONS}," == *,nomount,* ]] && [[ ",${ADDONS}," == *,zeromount,* ]]; then
        error "Addon conflict: 'nomount' and 'zeromount' both redirect VFS paths and cannot be combined — pick one."
    fi
    if [[ ",${ADDONS}," == *,zeromount,* ]] && addon_supports_kernel_version "zeromount" \
            && [ "${SUSFS_ENABLED:-false}" != "true" ]; then
        error "Addon conflict: 'zeromount' requires SuSFS (its readdir.c/namei.c/task_mmu.c hooks are SuSFS-baseline only, no non-SuSFS fallback) — enable SuSFS or pick a different mountless engine."
    fi

    export APPLIED_ADDONS="" SKIPPED_ADDONS=""
    for addon in "${ADDON_LIST[@]}"; do
        addon="${addon// /}"
        [ -z "$addon" ] && continue
        local script="${LUMINAIRE_PATCH_DIR}/kernel/addons/${addon}/${addon}.sh"
        if [ ! -f "$script" ]; then
            log "⚠️ Addon not found: ${addon}"
            continue
        fi
        if ! addon_supports_kernel_version "$addon"; then
            warn "Addon '${addon}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (shows as N/A, not Disable, in the release caption)."
            SKIPPED_ADDONS="${SKIPPED_ADDONS:+${SKIPPED_ADDONS},}${addon}"
            continue
        fi
        source "$script" || error "Addon failed: ${addon}"
        APPLIED_ADDONS="${APPLIED_ADDONS:+${APPLIED_ADDONS},}${addon}"
    done

    echo "APPLIED_ADDONS=${APPLIED_ADDONS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "SKIPPED_ADDONS=${SKIPPED_ADDONS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}
