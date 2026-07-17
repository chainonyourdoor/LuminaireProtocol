#!/usr/bin/env bash

# ======================================================
# 📁 SETUP — PATHS & BUILD CONFIG
# ======================================================

# Build system + Clang variant — parse combined input (e.g. "Make - Cirrus")
case "${BUILD_SYSTEM:-Make - Cirrus}" in
    Make\ -\ *)
        CLANG_VARIANT="${BUILD_SYSTEM##Make - }"
        CLANG_VARIANT="${CLANG_VARIANT,,}"
        BUILD_SYSTEM="MAKE"
        ;;
    MAKE)
        BUILD_SYSTEM="MAKE"
        CLANG_VARIANT="${CLANG_VARIANT:-cirrus}"
        ;;
    *)
        warn "Unknown BUILD_SYSTEM input '${BUILD_SYSTEM}', defaulting to MAKE + cirrus"
        BUILD_SYSTEM="MAKE"
        CLANG_VARIANT="cirrus"
        ;;
esac
export BUILD_SYSTEM CLANG_VARIANT

# Workspace
WORKSPACE_DIR="${ROOT_DIR}/workspace"
KERNEL_DIR="${WORKSPACE_DIR}/kernel"
KERNEL_SRC="${KERNEL_DIR}/common"
OUT_DIR="${WORKSPACE_DIR}/out"
LTO_CACHE_DIR="/dev/shm/ldcache"

# Patch repo paths
# LUMINAIRE_PATCH_DIR is bootstrapped by the entrypoint (build.sh/arsenal.sh)
# before run_setup() runs — it's what lets run_setup() find this very file.
# Guard here instead of silently re-deriving it, so a future entrypoint that
# forgets to set it fails loud instead of masking the mistake.
LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:?LUMINAIRE_PATCH_DIR must be set by the entrypoint before run_setup() runs}"
VERSION_PATCH_DIR="${LUMINAIRE_PATCH_DIR}/kernel/${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

# Build config
DEFCONFIG="gki_defconfig"
ARCH="arm64"

# Toolchain
TOOL_CLANG_DIR="${ROOT_DIR}/clang"
TOOL_AK3_DIR="${WORKSPACE_DIR}/AnyKernel3"
TOOL_CCACHE_BIN="${ROOT_DIR}/ccache-bin/ccache"
TOOL_CCACHE_WRAPPERS="${ROOT_DIR}/ccache-wrappers"
TOOL_CROSS_COMPILE="aarch64-linux-gnu-"
TOOL_CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"

# Kernel env
export GIT_CLONE_PROTECTION_ACTIVE=false
export KCFLAGS="-w"

log "Paths configured ✅ (Build System: ${BUILD_SYSTEM}, Clang: ${CLANG_VARIANT})"
