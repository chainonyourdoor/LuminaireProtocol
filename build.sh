#!/usr/bin/env bash
set -eo pipefail

exec 2>&1

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

ANDROID_VERSION="$(resolve_android_version)"
KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-live"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LUMINAIRE_PATCH_DIR="${ROOT_DIR}"

source "${LUMINAIRE_PATCH_DIR}/kernel/addons/registry.sh"
source "${LUMINAIRE_PATCH_DIR}/kernel/luminaire/registry.sh"
source "${LUMINAIRE_PATCH_DIR}/kernel/ksu-shared/registry.sh"

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

restore_kernel_source() {
    echo "::group::📥 Kernel Source"
    source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    log "Kernel source ready ✅"
    echo "::endgroup::"
}

run_branding() {
    echo "::group::🔖 Branding"
    source "${LUMINAIRE_PATCH_DIR}/kernel/branding.sh" || error "Branding failed!"
    echo "::endgroup::"
}

run_variant() {
    [ "$KERNEL_VARIANT" = "VANILLA" ] && return 0

    ksu_variant_supports_kernel_version "${KERNEL_VARIANT,,}" \
        || error "Root solution '${KERNEL_VARIANT}' is not available for kernel ${KERNEL_VERSION} — not listed in KSU_VARIANT_SUPPORTED_VERSIONS (kernel/ksu-shared/registry.sh)."
    local script="${LUMINAIRE_PATCH_DIR}/kernel/ksu-shared/${KERNEL_VARIANT,,}/${KERNEL_VARIANT,,}.sh"
    run_step "🍀" "Root Solution (${KERNEL_VARIANT})" "$script" \
        "Root solution '${KERNEL_VARIANT}' is marked supported for kernel ${KERNEL_VERSION} in KSU_VARIANT_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/ksu-shared/."

    [ "$SUSFS_ENABLED" = "true" ] || return 0
    local susfs_script="${VERSION_PATCH_DIR}/ksu/susfs/susfs.sh"
    run_step "🧬" "SuSFS" "$susfs_script" "SuSFS script not found: $(basename "$susfs_script")"
}

run_core() {
    echo "::group::🔧 Core"
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

run_build() {
    echo "::group::🏗️ Build Kernel (${BUILD_SYSTEM})"
    source "${LUMINAIRE_PATCH_DIR}/build/make.sh"
    echo "::endgroup::"
}

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

run_release() {
    echo "::group::🚀 Release"
    source "${LUMINAIRE_PATCH_DIR}/release/anykernel.sh" || error "Release failed: anykernel.sh"
    source "${LUMINAIRE_PATCH_DIR}/release/telegram/telegram.sh"  || error "Release failed: telegram.sh"
    echo "::endgroup::"
}

main "$@"
