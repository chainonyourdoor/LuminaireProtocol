#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Build Orchestrator
# ======================================================

set -eo pipefail

# GitHub Actions captures stdout and stderr as separate buffered streams and
# doesn't guarantee their relative order in the rendered log. log()/warn()/
# error() write to stderr while ::group::/::endgroup:: (below) write to
# stdout, so without this, log lines can render outside the ::group:: block
# they were actually written inside of. Merging stderr into stdout here
# keeps everything on one stream, preserving actual write order.
exec 2>&1

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

# DRY_RUN skips the actual compile (see build/make.sh) so
# the rest of the pipeline can be exercised quickly after a refactor. It's
# derived in build.yml from RUN_MODE=="Dry Run", so it can never disagree
# with RUN_MODE by the time it reaches here.

ANDROID_VERSION="$(resolve_android_version)"
KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Bootstrap path — needed before run_setup() sources 00_paths.sh
LUMINAIRE_PATCH_DIR="${ROOT_DIR}"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo "========================================"
    echo "  ✨ Luminaire Protocol ✨"
    echo "========================================"
    echo "  🏷️ ${KERNEL_VARIANT}$([ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ] && echo "+SUSFS")"
    echo "  $(mode_emoji "$RUN_MODE") ${RUN_MODE}"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "  📅 $(date)"
    echo "========================================"

    run_setup

    # Wait for background apt install (started in 01_deps.sh) to finish —
    # setup/02_ccache.sh (cmake/ninja/g++) and build/make.sh (bc/bison/flex)
    # need these packages present before they run. arsenal.sh already did
    # this; build.sh previously did not, which could race on a fresh runner.
    echo "::group::⏳ Dependencies"
    wait_for_apt
    echo "::endgroup::"

    [ -d "$VERSION_PATCH_DIR" ] \
        || error "Kernel version ${KERNEL_VERSION} is not yet supported — missing ${VERSION_PATCH_DIR} (no KSU/patches implemented for this version)"

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    restore_kernel_source
    run_branding
    run_variant
    mark_stage_ok CHECKPOINT_VARIANT_OK
    run_core
    run_luminaire
    run_addons
    mark_stage_ok CHECKPOINT_ADDONS_OK
    run_build
    run_postbuild

    if [ "${RUN_MODE^^}" = "WARM RUN" ]; then
        echo "========================================"
        echo "  $(mode_emoji "$RUN_MODE") ${RUN_MODE} Complete! $(mode_emoji "$RUN_MODE")"
        echo "  🏷️ ${KERNEL_VARIANT}$([ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ] && echo "+SUSFS")"
        echo "========================================"
        exit 0
    fi

    run_release

    echo "========================================"
    echo "  $(mode_emoji "$RUN_MODE") ${RUN_MODE} Complete! $(mode_emoji "$RUN_MODE")"
    echo "  🏷️ ${KERNEL_VARIANT}$([ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ] && echo "+SUSFS")"
    echo "========================================"
}


# ======================================================
# 📥 KERNEL SOURCE
# ======================================================
# (run_setup() is defined in functions.sh, shared with arsenal.sh)

restore_kernel_source() {
    echo "::group::📥 Kernel Source"
    source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    log "Kernel source ready ✅"
    echo "::endgroup::"
}

# ======================================================
# 🔖 BRANDING
# ======================================================

run_branding() {
    echo "::group::🔖 Branding"
    # || true on both greps below: grep exits 2 (not just 1) when handed a
    # file that doesn't exist — even if it found a match in the other file
    # given alongside it. build.config.constants doesn't exist on every
    # kernel version (confirmed missing on android12-5.10-lts's source,
    # present on android14-6.1-lts's), and under this script's set -eo
    # pipefail, that nonzero pipe exit was killing the script silently on
    # this exact line — before ever reaching the explicit error() checks
    # below, which is the only reason "KMI_GENERATION not found!" never
    # actually printed. The || true just lets those checks do their job.
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')" || true
    [ -n "$SUBLEVEL" ] || error "SUBLEVEL not found in kernel Makefile — kernel source may be missing or corrupted!"
    KMI_GENERATION="$(grep '^KMI_GENERATION=' \
        "${KERNEL_SRC}/build.config.common" \
        "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)" || true
    [ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found!"
    export SUBLEVEL KMI_GENERATION
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    source "${LUMINAIRE_PATCH_DIR}/kernel/branding.sh" || error "Branding failed!"
    echo "::endgroup::"
}

# ======================================================
# 🍀 ROOT SOLUTION & SUSFS
# ======================================================

run_variant() {
    local script="${VERSION_PATCH_DIR}/ksu/${KERNEL_VARIANT,,}/${KERNEL_VARIANT,,}.sh"
    if [ "$KERNEL_VARIANT" != "VANILLA" ]; then
        # Unlike addons, a missing root-solution script is not an optional
        # skip — the release label (Ak3-*-${KERNEL_VARIANT}-*.zip) is
        # identity-critical, so shipping vanilla under a KSUNEXT/etc label
        # because the variant script silently didn't exist for this kernel
        # version is worse than failing the build outright.
        [ -f "$script" ] || error "Root solution '${KERNEL_VARIANT}' is not available for kernel ${KERNEL_VERSION} — missing ${script}. Check kernel/${ANDROID_VERSION}-${KERNEL_VERSION}-lts/ksu/ for which variants actually exist on this version."
        echo "::group::🍀 Root Solution (${KERNEL_VARIANT})"
        source "$script" || error "Root solution script failed: $(basename "$script")"
        echo "::endgroup::"
    fi

    if [ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ]; then
        local susfs_script="${VERSION_PATCH_DIR}/ksu/susfs/susfs.sh"
        [ -f "$susfs_script" ] || error "SuSFS script not found: $(basename "$susfs_script")"
        echo "::group::🧬 SuSFS"
        source "$susfs_script" || error "SuSFS script failed: $(basename "$susfs_script")"
        echo "::endgroup::"
    fi
}

# ======================================================
# 🔧 CORE
# ======================================================

run_core() {
    echo "::group::🔧 Core"
    # Flat scripts first, then known subfolder orchestrators
    # Explicit list prevents accidental sourcing of temp/unrelated .sh files
    local core_dir="${LUMINAIRE_PATCH_DIR}/kernel/core"
    local scripts=(
        "${core_dir}/dirty_flag.sh"
        "${core_dir}/glibc.sh"
        "${core_dir}/protected_exports.sh"
        "${core_dir}/compiler_string/compiler_string.sh"
        "${core_dir}/module_bypass/module_bypass.sh"
        "${core_dir}/openssl3_compat/openssl3_compat.sh"
    )
    for script in "${scripts[@]}"; do
        [ -f "$script" ] || { warn "Core script not found: $(basename "$script") — skipping"; continue; }
        source "$script" || error "Core script failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# ✨ LUMINAIRE FEATURES (always-on, no toggle)
# ======================================================
# Structurally parallel to kernel/addons/, but never gated by $ADDONS or a
# workflow checkbox — these are permanent Luminaire-branded features
# (currently: ADIOS I/O scheduler, BORE CPU scheduler), always applied on
# every kernel version that has a backport for them, exactly the same way
# a distro ships its own default scheduler choice. See restructure plan
# Bug #2: these used to live in kernel/addons/ with a toggle in build.yml,
# which contradicted the actual intent (source was always patched in
# regardless of the toggle, only the Kconfig enable line and the release
# caption respected it).
#
# Space-separated KERNEL_VERSION values each feature actually has a patch
# for today — same shape/purpose as ADDON_SUPPORTED_VERSIONS below, kept
# as a separate map since these are never addons.
declare -A LUMINAIRE_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [adios]="6.1"
)

run_luminaire() {
    echo "::group::✨ Luminaire Features"
    local APPLIED_LUMINAIRE="" SKIPPED_LUMINAIRE=""
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

# ======================================================
# ⚡ ADDONS
# ======================================================

# ======================================================
# ⚡ ADDON KERNEL-VERSION SUPPORT MAP — single source of truth
# ======================================================
# Space-separated KERNEL_VERSION values each addon actually has a patch
# for today. This is the ONLY place that needs updating when a new
# backport lands for another kernel version — the addon's own .sh script
# stays generic (Pattern A: case-switch to an upstream URL keyed by
# version, e.g. ntsync/bbrv3/nomount/zeromount; or Pattern B: a
# self-maintained patch under kernel/<ver>-lts/patches/, e.g. droidspaces).
#
# ZeroMount's 5.10 entry: the kernel patch itself is confirmed to exist
# upstream (Enginex0/Super-Builders), but inject_namei.py/inject_readdir.py/
# fix_taskmmu.py's anchors were only ever verified against a 6.1 tree —
# they'll error() loudly if 5.10's SuSFS-patched namei.c/readdir.c don't
# match, rather than silently mis-patching, so this is a "probably fine,
# fails loud if not" entry, not a verified-safe one.
declare -A ADDON_SUPPORTED_VERSIONS=(
    [rekernel]="6.1"
    [bbrv3]="5.10 6.1"
    [bbg]="6.1"
    [droidspaces]="6.1"
    [ntsync]="5.10 6.1"
    [wireguard]="5.10 6.1"
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

    local APPLIED_ADDONS="" SKIPPED_ADDONS=""
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

# ======================================================
# 🏗️ BUILD
# ======================================================

run_build() {
    echo "::group::🏗️ Build Kernel (${BUILD_SYSTEM})"
    source "${LUMINAIRE_PATCH_DIR}/build/make.sh"
    echo "::endgroup::"
}

# ======================================================
# 🧩 POST-BUILD (per-addon)
# ======================================================
# Separate from run_addons()/run_build() on purpose: addons in run_addons()
# patch source/defconfig and get compiled as part of the single vmlinux
# build in run_build(). Some addons instead need work done AFTER run_build()
# finishes — e.g. Kasumi's out-of-tree LKM needs Module.symvers from the
# now-built kernel tree, which doesn't exist before that point.
#
# This is a thin dispatcher, same shape as run_build(): it doesn't know or
# care what any given addon's post-build step actually does (compile an
# LKM, whatever else some future addon needs) — it just runs
# kernel/addons/<name>/postbuild.sh for every enabled addon that has one.
# Addons without a postbuild.sh (the majority — anything patch/Kconfig-only)
# are silently skipped here, same gating as run_addons() (membership in
# $ADDONS), no separate per-addon "enabled" flag needed.

run_postbuild() {
    [ "${DRY_RUN:-false}" = "true" ] && return 0
    [ -z "${ADDONS:-}" ] && return 0

    echo "::group::🧩 Post-Build"

    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"
    for addon in "${ADDON_LIST[@]}"; do
        addon="${addon// /}"
        [ -z "$addon" ] && continue

        script="${LUMINAIRE_PATCH_DIR}/kernel/addons/${addon}/postbuild.sh"
        [ -f "$script" ] || continue

        log "🧩 Post-build: ${addon}"
        source "$script" || error "Post-build step failed: ${addon}"
    done

    echo "::endgroup::"
}

# ======================================================
# 🚀 RELEASE
# ======================================================

run_release() {
    echo "::group::🚀 Release"
    source "${LUMINAIRE_PATCH_DIR}/release/anykernel.sh" || error "Release failed: anykernel.sh"
    source "${LUMINAIRE_PATCH_DIR}/release/telegram/telegram.sh"  || error "Release failed: telegram.sh"
    echo "::endgroup::"
}

main "$@"
