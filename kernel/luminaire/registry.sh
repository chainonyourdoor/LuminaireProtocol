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
    local _lfo_csv
    IFS=, ; _lfo_csv="${LUMINAIRE_FEATURE_ORDER[*]}"; unset IFS
    echo "LUMINAIRE_FEATURE_ORDER=${_lfo_csv}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
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
    # Exported as a real shell env var here — AFTER the array-form loop
    # above is done with it, since this reuses the LUMINAIRE_FEATURE_ORDER
    # name as a plain string, which would break the loop if done earlier
    # — because caption.py runs later in this SAME step/process (build.sh
    # -> run_release() -> telegram.sh -> caption.py). $GITHUB_ENV (written
    # above) only takes effect starting the *next* Actions step, so a
    # same-step child process would never see it otherwise (see matching
    # fix in kernel/addons/registry.sh's run_addons() for the addon-side
    # bug this was copied from).
    # LUMINAIRE_FEATURE_ORDER is declared as an indexed array at the top
    # of this file (global scope) — `export NAME=string` on an existing
    # array only overwrites element [0], it does NOT convert it to a
    # scalar, so a subprocess (python3 caption.py) would still see
    # nothing usable. Must unset the array first (safe here: the loop
    # above is the only place in this script that needs it as an array).
    unset LUMINAIRE_FEATURE_ORDER
    export LUMINAIRE_FEATURE_ORDER="${_lfo_csv}"
    echo "APPLIED_LUMINAIRE=${APPLIED_LUMINAIRE}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "SKIPPED_LUMINAIRE=${SKIPPED_LUMINAIRE}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}
