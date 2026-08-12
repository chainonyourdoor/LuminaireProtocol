#!/usr/bin/env bash

declare -A TUNING_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [adios]="6.1"
    [le9uo]="6.1"
    [kcompressd]="6.1"
    [workqueue_catchup]="6.1"
    [schedutil_catchup]="6.1"
    [ufs_writebooster_catchup]="6.1"
)

TUNING_FEATURE_ORDER=(bore adios le9uo kcompressd workqueue_catchup schedutil_catchup ufs_writebooster_catchup)

run_tuning() {
    echo "::group::✨ Tuning Features"
    export APPLIED_TUNING="" SKIPPED_TUNING=""
    local _tfo_csv
    IFS=, ; _tfo_csv="${TUNING_FEATURE_ORDER[*]}"; unset IFS
    echo "TUNING_FEATURE_ORDER=${_tfo_csv}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    for feature in "${TUNING_FEATURE_ORDER[@]}"; do
        local supported="${TUNING_SUPPORTED_VERSIONS[$feature]:-}"
        if [[ " ${supported} " != *" ${KERNEL_VERSION} "* ]]; then
            warn "Tuning feature '${feature}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (always-on, not a user toggle; shows as N/A in the release caption, not a Disable)."
            SKIPPED_TUNING="${SKIPPED_TUNING:+${SKIPPED_TUNING},}${feature}"
            continue
        fi
        local script="${LUMINAIRE_PATCH_DIR}/kernel/tuning/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Tuning feature '${feature}' is marked supported for kernel ${KERNEL_VERSION} in TUNING_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/tuning/."
        source "$script" || error "Tuning feature failed: ${feature}"
        APPLIED_TUNING="${APPLIED_TUNING:+${APPLIED_TUNING},}${feature}"
    done

    unset TUNING_FEATURE_ORDER
    export TUNING_FEATURE_ORDER="${_tfo_csv}"
    echo "APPLIED_TUNING=${APPLIED_TUNING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "SKIPPED_TUNING=${SKIPPED_TUNING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}
