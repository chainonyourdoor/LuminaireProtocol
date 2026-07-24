#!/usr/bin/env bash

declare -A LUMINAIRE_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [adios]="6.1"
    [workqueue_catchup]="6.1"
    [schedutil_catchup]="6.1"
    [ufs_writebooster_catchup]="6.1"
)

# Single source of truth for iteration/display order — bash associative
# array key order is unspecified, so this can't be derived from
# LUMINAIRE_SUPPORTED_VERSIONS above; keep both in sync when adding a
# feature. Exported so release/telegram/caption.py can build its
# feature table dynamically instead of hardcoding this list too.
LUMINAIRE_FEATURE_ORDER=(bore adios workqueue_catchup schedutil_catchup ufs_writebooster_catchup)

run_luminaire() {
    echo "::group::✨ Luminaire Features"
    export APPLIED_LUMINAIRE="" SKIPPED_LUMINAIRE=""
    IFS=, ; echo "LUMINAIRE_FEATURE_ORDER=${LUMINAIRE_FEATURE_ORDER[*]}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true; unset IFS
    for feature in "${LUMINAIRE_FEATURE_ORDER[@]}"; do
        local supported="${LUMINAIRE_SUPPORTED_VERSIONS[$feature]:-}"
        if [[ " ${supported} " != *" ${KERNEL_VERSION} "* ]]; then
            warn "Luminaire feature '${feature}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (always-on, not a user toggle; shows as N/A in the release caption, not a Disable)."
            SKIPPED_LUMINAIRE="${SKIPPED_LUMINAIRE:+${SKIPPED_LUMINAIRE},}${feature}"
            continue
        fi
        local script="${LUMINAIRE_PATCH_DIR}/kernel/luminaire/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Luminaire feature '${feature}' is marked supported for kernel ${KERNEL_VERSION} in LUMINAIRE_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/luminaire/."
        source "$script" || error "Luminaire feature failed: ${feature}"
        APPLIED_LUMINAIRE="${APPLIED_LUMINAIRE:+${APPLIED_LUMINAIRE},}${feature}"
    done
    echo "APPLIED_LUMINAIRE=${APPLIED_LUMINAIRE}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "SKIPPED_LUMINAIRE=${SKIPPED_LUMINAIRE}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}
