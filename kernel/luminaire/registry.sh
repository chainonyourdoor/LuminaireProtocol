#!/usr/bin/env bash

declare -A LUMINAIRE_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [adios]="6.1"
)

run_luminaire() {
    echo "::group::✨ Luminaire Features"
    export APPLIED_LUMINAIRE="" SKIPPED_LUMINAIRE=""
    for feature in bore adios; do
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
