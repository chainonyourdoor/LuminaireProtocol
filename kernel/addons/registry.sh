#!/usr/bin/env bash

# ======================================================
# ⚡ ADDON REGISTRY — support map, conflicts, dispatch
# ======================================================
# Sourced once by build.sh (functions become available for the rest of the
# process, same shape as functions.sh) so build.sh itself only ever calls
# run_addons() and doesn't need to know any addon policy lives here.

# ======================================================
# ⚡ ADDON KERNEL-VERSION SUPPORT MAP — single source of truth
# ======================================================
# Space-separated KERNEL_VERSION values each addon actually has a patch
# for today. This is the ONLY place that needs updating when a new
# backport lands for another kernel version — the addon's own .sh script
# stays generic (Pattern A: case-switch to an upstream URL keyed by
# version, e.g. ntsync/bbrv3/nomount/zeromount; or Pattern B: a
# self-maintained patch under kernel/<ver>/patches/, e.g. droidspaces).
#
# ZeroMount's 5.10 entry: the kernel patch itself is confirmed to exist
# upstream (Enginex0/Super-Builders), but inject_namei.py/inject_readdir.py/
# fix_taskmmu.py's anchors were only ever verified against a 6.1 tree —
# they'll error() loudly if 5.10's SuSFS-patched namei.c/readdir.c don't
# match, rather than silently mis-patching, so this is a "probably fine,
# fails loud if not" entry, not a verified-safe one.
declare -A ADDON_SUPPORTED_VERSIONS=(
    [rekernel]="6.1"
    [bbrv3]="5.10 5.15 6.1"
    [bbg]="6.1"
    [droidspaces]="6.1"
    [ntsync]="5.10 5.15 6.1"
    [wireguard]="5.10 5.15 6.1"
    [lz4zstd]="6.1"
    [lz4kd]="6.1"
    [kasumi]="6.1"
    [nomount]="5.10 6.1"
    [zeromount]="5.10 6.1"
)

addon_supports_kernel_version() {
    local addon="$1"
    local supported="${ADDON_SUPPORTED_VERSIONS[$addon]:-}"
    # Unknown addon name -> treat as unsupported rather than silently
    # letting it through; ADDON_SUPPORTED_VERSIONS should be kept in sync
    # with kernel/addons/*/*.sh (same list release/telegram/caption.py's
    # TOGGLE_ADDON_ORDER tracks).
    [ -z "$supported" ] && return 1
    [[ " ${supported} " == *" ${KERNEL_VERSION} "* ]]
}

run_addons() {
    [ -z "${ADDONS:-}" ] && return 0
    # Strip whitespace, leading/trailing commas, and duplicate commas
    ADDONS="${ADDONS// /}"
    ADDONS="$(echo "$ADDONS" | sed 's/^,*//;s/,*$//;s/,,*/,/g')"
    [ -z "${ADDONS}" ] && return 0
    echo "::group::⚡ Addons"
    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"

    # Conflict matrix — addons that patch overlapping kernel subsystems and
    # cannot be safely combined. Checked up front so a bad combo fails fast
    # instead of leaving a half-patched tree mid-build.
    if [[ ",${ADDONS}," == *,nomount,* ]] && [[ ",${ADDONS}," == *,zeromount,* ]]; then
        error "Addon conflict: 'nomount' and 'zeromount' both redirect VFS paths and cannot be combined — pick one."
    fi
    if [[ ",${ADDONS}," == *,zeromount,* ]] && [ "${SUSFS_ENABLED:-false}" != "true" ]; then
        error "Addon conflict: 'zeromount' requires SuSFS (its readdir.c/namei.c/task_mmu.c hooks are SuSFS-baseline only, no non-SuSFS fallback) — enable SuSFS or pick a different mountless engine."
    fi

    # Not local — same reason as APPLIED_LUMINAIRE/SKIPPED_LUMINAIRE in
    # kernel/luminaire/registry.sh: telegram.sh reads these later in the
    # same process to build the release caption.
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
