#!/usr/bin/env bash

# ======================================================
# 🏗️ BUILD — KLEAF (Bazel)
# ======================================================

if [ ${#BRANDING_KLEAF_ARGS[@]} -eq 0 ]; then
    error "BRANDING_KLEAF_ARGS is empty — branding.sh may not have run correctly!"
fi

KLEAF_ARGS=(
    --config=fast
    --lto="${ENABLE_LTO,,}"
    "${BRANDING_KLEAF_ARGS[@]}"
)

# Ensure LTO cache dir exists on RAM disk
mkdir -p "$LTO_CACHE_DIR"

log "Applying Luminaire configs (fragment)..."
DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
while IFS= read -r line; do
    [[ "$line" =~ ^(CONFIG_[^=]+)=(.*)$ ]] || \
    [[ "$line" =~ ^(# CONFIG_[^ ]+) is not set$ ]] || continue

    if [[ "$line" =~ ^CONFIG_([^=]+)=(.*)$ ]]; then
        key="CONFIG_${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        # Remove existing entry (set or unset) then append — mirrors merge_config.sh -m
        sed -i "/^${key}[= ]/d;/^# ${key} is not set/d" "$DEFCONFIG"
        echo "${key}=${val}" >> "$DEFCONFIG"
    elif [[ "$line" =~ ^# (CONFIG_[^ ]+) is not set$ ]]; then
        key="${BASH_REMATCH[1]}"
        sed -i "/^${key}[= ]/d;/^# ${key} is not set/d" "$DEFCONFIG"
        echo "# ${key} is not set" >> "$DEFCONFIG"
    fi
done < <(grep -E '^CONFIG_|^# CONFIG_' "${LUMINAIRE_PATCH_DIR}/kernel/config/luminaire.fragment")
log "Fragment applied ✅"

log "Running config pass to canonicalize gki_defconfig..."
cd "$KERNEL_DIR"
tools/bazel build "${KLEAF_ARGS[@]}" //common:kernel_aarch64_config

CANONICAL=$(find "${KERNEL_DIR}/out" -path "*/common/defconfig" 2>/dev/null | head -1)
if [ -n "$CANONICAL" ]; then
    cp "$CANONICAL" "$DEFCONFIG"
    log "gki_defconfig canonicalized ✅ (from $(basename $(dirname $CANONICAL))/defconfig)"
else
    error "Canonical defconfig not found — config pass may have failed early"
fi
cd "$ROOT_DIR"
log "Fragment applied ✅"

log "Applying version patches..."
for patch in "${VERSION_PATCH_DIR}/patches/"*.patch; do
    [ -f "$patch" ] || continue
    log "Applying: $(basename "$patch")..."
    if patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
        patch -p1 --fuzz=3 -d "$KERNEL_SRC" < "$patch" || error "Patch failed: $(basename "$patch")"
        log "$(basename "$patch") applied ✅"
    elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
        log "$(basename "$patch") already applied, skipping."
    else
        error "$(basename "$patch") failed — conflict!"
    fi
done

log "Building kernel with Kleaf (Bazel)..."
START_TIME=$(date +%s)

cd "$KERNEL_DIR"
tools/bazel build "${KLEAF_ARGS[@]}" //common:kernel_aarch64 \
    || error "Kleaf build failed!"
cd "$ROOT_DIR"

BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
log "Kleaf build completed in ${BUILD_SECONDS}s ✅"
echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

log "Detecting AOSP Clang version used by Kleaf..."
AOSP_CLANG_BIN=$(find "${KERNEL_DIR}/prebuilts/clang/host/linux-x86" \
    -maxdepth 3 -name clang -path "*/bin/clang" 2>/dev/null | head -1)
if [ -n "$AOSP_CLANG_BIN" ]; then
    set +o pipefail
    AOSP_CLANG_VER=$("$AOSP_CLANG_BIN" --version 2>&1 | grep -oP 'clang version \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    set -o pipefail
    if [ -n "$AOSP_CLANG_VER" ]; then
        COMPILER_STRING="AOSP Clang ${AOSP_CLANG_VER}"
    else
        COMPILER_STRING="AOSP Clang"
        warn "Could not parse AOSP Clang version from -v output"
    fi
    export COMPILER_STRING
    echo "COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    log "Compiler: ${COMPILER_STRING:-N/A} ✅"
else
    warn "AOSP Clang binary not found — COMPILER_STRING will be unset"
fi
