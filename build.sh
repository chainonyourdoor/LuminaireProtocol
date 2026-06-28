#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Build Orchestrator
# ======================================================

set -eo pipefail

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

case "${KERNEL_VERSION}" in
  "5.10") ANDROID_VERSION="android13" ;;
  "5.15") ANDROID_VERSION="android13" ;;
  "6.1")  ANDROID_VERSION="android14" ;;
  "6.6")  ANDROID_VERSION="android15" ;;
  "6.12") ANDROID_VERSION="android16" ;;
  *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
esac

KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Bootstrap path — needed before run_setup() sources 00_paths.sh
LUMINAIRE_PATCH_DIR="${ROOT_DIR}/luminaire"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo "========================================"
    echo "  ✨ Luminaire Protocol — ${ROOT_SOLUTION}$([ "$SUSFS_ENABLED" = "true" ] && [ "$ROOT_SOLUTION" != "VANILLA" ] && echo "+SUSFS")"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "  📅 $(date)"
    echo "========================================"

    run_setup

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    restore_kernel_source
    run_branding
    run_variant
    run_core
    run_addons
    run_build

    if [ "$WARMING_MODE" = "true" ]; then
        log "🔥 Warming Complete — skipping packaging"
        exit 0
    fi

    run_release

    echo "========================================"
    echo "  Build Complete! — ${ZIP_NAME}"
    echo "========================================"
}


# ======================================================
# 📦 SETUP
# ======================================================

run_setup() {
    echo "::group::📦 Setup"
    for script in "${LUMINAIRE_PATCH_DIR}/setup/"*.sh; do
        source "$script" || error "Setup failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# 📥 KERNEL SOURCE
# ======================================================

restore_kernel_source() {
    echo "::group::📥 Kernel Source"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${LUMINAIRE_PATCH_DIR}/download/kleaf.sh"
    else
        source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    fi
    log "Kernel source ready ✅"
    echo "::endgroup::"
}

# ======================================================
# 🏷️ BRANDING
# ======================================================

run_branding() {
    echo "::group::🏷️ Branding"
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')"
    [ -n "$SUBLEVEL" ] || error "SUBLEVEL not found in kernel Makefile — kernel source may be missing or corrupted!"
    KMI_GENERATION="$(grep '^KMI_GENERATION=' \
        "${KERNEL_SRC}/build.config.common" \
        "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)"
    [ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found!"
    export SUBLEVEL KMI_GENERATION
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    source "${LUMINAIRE_PATCH_DIR}/kernel/branding.sh" || error "Branding failed!"
    echo "::endgroup::"
}

# ======================================================
# 🔑 ROOT SOLUTION & SUSFS
# ======================================================

run_variant() {
    local script="${VERSION_PATCH_DIR}/ksu/${ROOT_SOLUTION,,}/${ROOT_SOLUTION,,}.sh"
    if [ -f "$script" ]; then
        echo "::group::🔑 Root Solution (${ROOT_SOLUTION})"
        source "$script" || error "Root solution script failed: $(basename "$script")"
        echo "::endgroup::"
    fi

    if [ "$SUSFS_ENABLED" = "true" ] && [ "$ROOT_SOLUTION" != "VANILLA" ]; then
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
    )
    for script in "${scripts[@]}"; do
        [ -f "$script" ] || { warn "Core script not found: $(basename "$script") — skipping"; continue; }
        source "$script" || error "Core script failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# ⚡ ADDONS
# ======================================================

run_addons() {
    [ -z "${ADDONS:-}" ] && return 0
    # Strip whitespace, leading/trailing commas, dan koma ganda
    ADDONS="${ADDONS// /}"
    ADDONS="$(echo "$ADDONS" | sed 's/^,*//;s/,*$//;s/,,*/,/g')"
    [ -z "${ADDONS}" ] && return 0
    echo "::group::⚡ Addons"
    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"
    for addon in "${ADDON_LIST[@]}"; do
        addon="${addon// /}"
        [ -z "$addon" ] && continue
        local script="${LUMINAIRE_PATCH_DIR}/kernel/addons/${addon}/${addon}.sh"
        # Fallback to flat structure for addons without subfolder (droidspaces, nomount)
        [ -f "$script" ] || script="${LUMINAIRE_PATCH_DIR}/kernel/addons/${addon}.sh"
        if [ -f "$script" ]; then
            source "$script" || error "Addon failed: ${addon}"
        else
            log "⚠️ Addon not found: ${addon}"
        fi
    done
    echo "::endgroup::"
}

# ======================================================
# 🏗️ BUILD
# ======================================================

run_build() {
    echo "::group::🏗️ Build Kernel (${BUILD_SYSTEM})"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${LUMINAIRE_PATCH_DIR}/build/kleaf.sh"
    else
        source "${LUMINAIRE_PATCH_DIR}/build/make.sh"
    fi
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
