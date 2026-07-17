#!/usr/bin/env bash

# ======================================================
# 🧰 SETUP — CLANG DISPATCHER
# ======================================================

CLANG_CACHE_DIR="${HOME}/clang-cache"

if [ "${USE_CLANG_CACHE}" = "true" ] && [ -d "${CLANG_CACHE_DIR}/bin" ]; then
    log "Restoring Clang from cache (${CLANG_VARIANT})..."
    mkdir -p "$TOOL_CLANG_DIR"
    cp -a "${CLANG_CACHE_DIR}/." "${TOOL_CLANG_DIR}/"
    # actions/cache does not always preserve file permissions — fix after restore
    chmod +x "${TOOL_CLANG_DIR}/bin/"* 2>/dev/null || true
    # Restore glibc compat libs if they were cached alongside clang
    if [ -d "${CLANG_CACHE_DIR}/.neutron-tc-cache" ] && [ ! -d "${HOME}/.neutron-tc" ]; then
        cp -a "${CLANG_CACHE_DIR}/.neutron-tc-cache" "${HOME}/.neutron-tc"
    fi
    if ! "${TOOL_CLANG_DIR}/bin/clang" --version > /dev/null 2>&1; then
        warn "Clang binary not executable after cache restore — re-downloading..."
        rm -rf "$TOOL_CLANG_DIR" "$CLANG_CACHE_DIR"
        mkdir -p "$TOOL_CLANG_DIR"
        CLANG_VARIANT_SCRIPT="${LUMINAIRE_PATCH_DIR}/setup/clang/${CLANG_VARIANT}.sh"
        [ -f "$CLANG_VARIANT_SCRIPT" ] || error "Clang variant script not found: ${CLANG_VARIANT}"
        source "$CLANG_VARIANT_SCRIPT"
        [ -d "${TOOL_CLANG_DIR}/bin" ] || error "Clang binary missing after re-download!"
        mkdir -p "$CLANG_CACHE_DIR"
        cp -a "${TOOL_CLANG_DIR}/." "${CLANG_CACHE_DIR}/"
        if [ -d "${HOME}/.neutron-tc" ]; then
            cp -a "${HOME}/.neutron-tc" "${CLANG_CACHE_DIR}/.neutron-tc-cache"
        fi
        # Workflow always re-saves clang cache after this step regardless
        log "Clang re-downloaded and cached ✅"
    else
        log "Clang restored ✅ ($(cache_freshness_note))"
    fi
else
    mkdir -p "$TOOL_CLANG_DIR"
    CLANG_VARIANT_SCRIPT="${LUMINAIRE_PATCH_DIR}/setup/clang/${CLANG_VARIANT}.sh"
    [ -f "$CLANG_VARIANT_SCRIPT" ] || error "Clang variant script not found: ${CLANG_VARIANT}"
    source "$CLANG_VARIANT_SCRIPT"
    [ -d "${TOOL_CLANG_DIR}/bin" ] || error "Clang binary missing after download — ${CLANG_VARIANT} script may have failed!"
    mkdir -p "$CLANG_CACHE_DIR"
    cp -a "${TOOL_CLANG_DIR}/." "${CLANG_CACHE_DIR}/"
    # Also cache glibc compat libs (e.g. ~/.neutron-tc) so restored binary
    # can load patched interpreter without re-running antman --patch=glibc
    if [ -d "${HOME}/.neutron-tc" ]; then
        cp -a "${HOME}/.neutron-tc" "${CLANG_CACHE_DIR}/.neutron-tc-cache"
    fi
    log "Clang cached ✅"
fi

set +o pipefail
CLANG_VERSION=$("${TOOL_CLANG_DIR}/bin/clang" --version 2>&1 \
    | grep -oP 'clang version \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
set -o pipefail

case "$CLANG_VARIANT" in
    cirrus)  CLANG_BRAND="Cirrus Clang" ;;
    neutron) CLANG_BRAND="Neutron Clang" ;;
    weebx)   CLANG_BRAND="WeebX Clang" ;;
    zyc)     CLANG_BRAND="ZyC Clang" ;;
    *)       CLANG_BRAND="${CLANG_VARIANT} Clang" ;;
esac

if [ -n "$CLANG_VERSION" ]; then
    COMPILER_STRING="${CLANG_BRAND} ${CLANG_VERSION}"
else
    COMPILER_STRING="$CLANG_BRAND"
    warn "Could not parse Clang version from --version output"
fi

export COMPILER_STRING
echo "COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
export PATH="${TOOL_CLANG_DIR}/bin:${PATH}"

log "Setting up ccache wrappers..."
mkdir -p "$TOOL_CCACHE_WRAPPERS"

for tool in $(ls "${TOOL_CLANG_DIR}/bin/" | grep -E "^clang(\+\+)?(-[0-9]+)?$"); do
    REAL_BIN="${TOOL_CLANG_DIR}/bin/${tool}"
    WRAPPER="${TOOL_CCACHE_WRAPPERS}/${tool}"
    cat > "$WRAPPER" << WRAPPER_EOF
#!/usr/bin/env bash
exec "${TOOL_CCACHE_BIN}" "${REAL_BIN}" "\$@"
WRAPPER_EOF
    chmod +x "$WRAPPER"
done
export PATH="${TOOL_CCACHE_WRAPPERS}:${PATH}"
echo "${TOOL_CCACHE_WRAPPERS}" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
echo "${TOOL_CLANG_DIR}/bin" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
log "Clang ready | ${COMPILER_STRING} ✅"
