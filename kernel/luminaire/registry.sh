#!/usr/bin/env bash

# ======================================================
# ✨ LUMINAIRE FEATURE REGISTRY — support map, dispatch
# ======================================================
# Sourced once by build.sh (functions become available for the rest of the
# process, same shape as functions.sh) so build.sh itself only ever calls
# run_luminaire() and doesn't need to know any feature policy lives here.
#
# These features (currently: ADIOS I/O scheduler, BORE CPU scheduler) are
# structurally parallel to kernel/addons/, but never gated by $ADDONS or a
# workflow checkbox — they're permanent Luminaire-branded features, always
# applied on every kernel version that has a backport for them, exactly the
# same way a distro ships its own default scheduler choice. See restructure
# plan Bug #2: these used to live in kernel/addons/ with a toggle in
# build.yml, which contradicted the actual intent (source was always
# patched in regardless of the toggle, only the Kconfig enable line and the
# release caption respected it).
#
# Space-separated KERNEL_VERSION values each feature actually has a patch
# for today — same shape/purpose as kernel/addons/registry.sh's
# ADDON_SUPPORTED_VERSIONS, kept as a separate map since these are never
# addons.
declare -A LUMINAIRE_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [adios]="6.1"
)

run_luminaire() {
    echo "::group::✨ Luminaire Features"
    # Not local: telegram.sh (run_release -> telegram.sh, later in the same
    # process) reads these directly to build the release caption. A
    # function-local var dies at return, so it would never survive to
    # reach telegram.sh even though both run in the same bash process —
    # see Bug #4.
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
