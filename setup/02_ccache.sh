#!/usr/bin/env bash

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
export CCACHE_BASEDIR="$KERNEL_SRC"
export CCACHE_IS_KERNEL_COMPILING="true"
export CCACHE_COMPILERCHECK="none"
export CCACHE_NOHASHDIR="true"
export CCACHE_NOHARDLINK="true"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1

[ -n "${CCACHE_DIR}" ] || error "ccache: CCACHE_DIR is not set!"
[ -n "${CCACHE_MAXSIZE}" ] || error "ccache: CCACHE_MAXSIZE is not set!"

mkdir -p "${CCACHE_DIR}"
echo "sloppiness = include_file_ctime,include_file_mtime,pch_defines,file_macro,time_macros" \
    >> "${CCACHE_DIR}/ccache.conf"

${TOOL_CCACHE_BIN} --zero-stats > /dev/null 2>&1 || true
log "ccache ready | dir: ${CCACHE_DIR} | max: ${CCACHE_MAXSIZE}"
