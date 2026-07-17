#!/usr/bin/env bash

# ======================================================
# ⚡ SETUP — CCACHE-ECS
# ======================================================

CCACHE_CACHE_DIR="${HOME}/ccache-bin"

if [ -f "${CCACHE_CACHE_DIR}/ccache" ]; then
    log "Restoring ccache-ECS from cache..."
    mkdir -p "${ROOT_DIR}/ccache-bin"
    cp "${CCACHE_CACHE_DIR}/ccache" "${ROOT_DIR}/ccache-bin/ccache"
    chmod +x "${ROOT_DIR}/ccache-bin/ccache"
    log "ccache-ECS restored ✅ ($(cache_freshness_note))"
else
    log "Building ccache-ECS from source..."
    retry 3 run_quiet git clone --depth=1 -b ccache-ECS-v1.0 \
        https://github.com/cctv18/ccache-ECS /tmp/ccache-ECS \
        || error "Failed to clone ccache-ECS! (see output above)"
    cmake -S /tmp/ccache-ECS -B /tmp/ccache-build \
        -GNinja -DCMAKE_BUILD_TYPE=Release \
        -DZSTD_FROM_INTERNET=OFF -DENABLE_TESTING=OFF \
        -DENABLE_DOCUMENTATION=OFF -DENABLE_IPO=ON \
        -DREDIS_STORAGE_BACKEND=OFF \
        -DHTTP_STORAGE_BACKEND=OFF > /dev/null 2>&1
    cmake --build /tmp/ccache-build -j$(nproc) > /dev/null 2>&1
    mkdir -p "${CCACHE_CACHE_DIR}" "${ROOT_DIR}/ccache-bin"
    cp /tmp/ccache-build/ccache "${CCACHE_CACHE_DIR}/ccache"
    cp /tmp/ccache-build/ccache "${ROOT_DIR}/ccache-bin/ccache"
    chmod +x "${ROOT_DIR}/ccache-bin/ccache"
    log "ccache-ECS built and cached ✅"
fi

export CCACHE_COMPILER="${TOOL_CLANG_DIR}/bin/clang"
# Note: TOOL_CLANG_DIR/bin/clang is not yet on disk at this point —
# 03_clang.sh downloads it next. CCACHE_COMPILER is read by ccache at
# compile time (not at export time), so this is safe as long as clang
# is in place before any make invocation. The || check in 03_clang.sh
# guarantees that.
export CCACHE_BASEDIR="$KERNEL_SRC"
export CCACHE_IS_KERNEL_COMPILING="true"
export CCACHE_COMPILERCHECK="none"
export CCACHE_NOHASHDIR="true"
export CCACHE_NOHARDLINK="true"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1

[ -n "${CCACHE_DIR}" ] || error "ccache: CCACHE_DIR is not set!"
[ -n "${CCACHE_MAXSIZE}" ] || error "ccache: CCACHE_MAXSIZE is not set!"

# Write sloppiness config — allows ccache-ECS to ignore file timestamps,
# ctime, mtime, and time macros for cache validation
mkdir -p "${CCACHE_DIR}"
echo "sloppiness = file_stat_matches,include_file_ctime,include_file_mtime,pch_defines,file_macro,time_macros" \
    >> "${CCACHE_DIR}/ccache.conf"

# Reset stats (not cache data) for fresh tracking
${TOOL_CCACHE_BIN} --zero-stats > /dev/null 2>&1 || true
log "ccache ready | dir: ${CCACHE_DIR} | max: ${CCACHE_MAXSIZE}"
