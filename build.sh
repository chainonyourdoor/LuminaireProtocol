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

# Registries define run_addons()/run_luminaire() (plus their version-support
# maps) — sourced here, not inside main(), so they're just ordinary function
# calls in main() like everything else, and build.sh never has to know any
# addon/luminaire policy itself.
source "${LUMINAIRE_PATCH_DIR}/kernel/addons/registry.sh"
source "${LUMINAIRE_PATCH_DIR}/kernel/luminaire/registry.sh"
source "${LUMINAIRE_PATCH_DIR}/kernel/ksu-shared/registry.sh"

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
    mark_stage_ok CHECKPOINT_BUILD_OK
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
    source "${LUMINAIRE_PATCH_DIR}/kernel/branding.sh" || error "Branding failed!"
    echo "::endgroup::"
}

# ======================================================
# 🍀 ROOT SOLUTION & SUSFS
# ======================================================

run_variant() {
    [ "$KERNEL_VARIANT" = "VANILLA" ] && return 0

    # Unlike addons, an unsupported root solution is not an optional skip
    # — the release label (Ak3-*-${KERNEL_VARIANT}-*.zip) is
    # identity-critical, so shipping vanilla under a KSUNEXT/etc label
    # because the variant wasn't supported for this kernel version is
    # worse than failing the build outright.
    ksu_variant_supports_kernel_version "${KERNEL_VARIANT,,}" \
        || error "Root solution '${KERNEL_VARIANT}' is not available for kernel ${KERNEL_VERSION} — not listed in KSU_VARIANT_SUPPORTED_VERSIONS (kernel/ksu-shared/registry.sh)."
    local script="${LUMINAIRE_PATCH_DIR}/kernel/ksu-shared/${KERNEL_VARIANT,,}/${KERNEL_VARIANT,,}.sh"
    run_step "🍀" "Root Solution (${KERNEL_VARIANT})" "$script" \
        "Root solution '${KERNEL_VARIANT}' is marked supported for kernel ${KERNEL_VERSION} in KSU_VARIANT_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/ksu-shared/."

    [ "$SUSFS_ENABLED" = "true" ] || return 0
    local susfs_script="${VERSION_PATCH_DIR}/ksu/susfs/susfs.sh"
    run_step "🧬" "SuSFS" "$susfs_script" "SuSFS script not found: $(basename "$susfs_script")"
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
# ✨ LUMINAIRE FEATURES & ⚡ ADDONS
# ======================================================
# run_luminaire() and run_addons() (plus their version-support maps and
# the addon conflict matrix) live in kernel/luminaire/registry.sh and
# kernel/addons/registry.sh respectively — sourced near the top of this
# file. Kept out of build.sh itself so this file stays an orchestrator
# (decides *when* things run) rather than also owning *what's supported*.

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
# kernel/addons/<name>/postbuild.sh for every *applied* addon that has one.
# Gates on membership in $APPLIED_ADDONS (the post-version-filtering list
# from run_addons()), not raw $ADDONS — an addon skipped there (kernel
# version unsupported) never got its main script run, so its exported
# state (e.g. Kasumi's $KASUMI_SRC_DIR) never existed either. Gating on
# raw $ADDONS here would still try to run its postbuild.sh and fail on
# that missing state. Addons without a postbuild.sh (the majority —
# anything patch/Kconfig-only) are silently skipped here, no separate
# per-addon "enabled" flag needed.

run_postbuild() {
    [ "${DRY_RUN:-false}" = "true" ] && return 0
    [ -z "${APPLIED_ADDONS:-}" ] && return 0

    echo "::group::🧩 Post-Build"

    IFS=',' read -ra ADDON_LIST <<< "$APPLIED_ADDONS"
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
