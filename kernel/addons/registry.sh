#!/usr/bin/env bash

declare -A ADDON_SUPPORTED_VERSIONS=(
    [nomount]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [zeromount]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [bbrv3]="5.10 5.15 6.1 6.6 6.6-konoha"
    [bbg]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [wireguard]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [droidspaces]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [rekernel]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [kpatch-next]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
    [ntsync]="5.10 5.15 6.1 6.6 6.6-konoha"
    [lz4zstd]="6.1"
    [lz4kd]="5.10 5.15 6.1 6.6 6.6-konoha"
    [kasumi]="5.10 5.15 6.1 6.6 6.12 6.6-konoha"
)

ADDON_ORDER=(nomount zeromount bbrv3 bbg wireguard droidspaces rekernel kpatch-next ntsync lz4zstd lz4kd kasumi)

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

    if [[ ",${ADDONS}," == *,nomount,* ]] && [[ ",${ADDONS}," == *,zeromount,* ]]; then
        error "Addon conflict: 'nomount' and 'zeromount' both redirect VFS paths and cannot be combined — pick one."
    fi

    export APPLIED_ADDONS="" SKIPPED_ADDONS=""

    if [[ ",${ADDONS}," == *,zeromount,* ]] && addon_supports_kernel_version "zeromount" \
            && [ "${SUSFS_ENABLED:-false}" != "true" ]; then
        warn "Addon 'zeromount' requires SuSFS (its readdir.c/namei.c/task_mmu.c hooks are SuSFS-baseline only, no non-SuSFS fallback) — skipping (SuSFS not enabled for this build)."
        ADDONS="$(printf ',%s,' "$ADDONS" | sed 's/,zeromount,/,/g' | sed 's/^,//;s/,$//')"
        SKIPPED_ADDONS="zeromount"
    fi

    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"
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
