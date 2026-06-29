#!/usr/bin/env bash

# ======================================================
# 🏗️ BUILD — MAKE
# ======================================================

MAKE_ARGS=(
    -C "$KERNEL_SRC"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CROSS_COMPILE="$TOOL_CROSS_COMPILE"
    CROSS_COMPILE_COMPAT="$TOOL_CROSS_COMPILE_COMPAT"
    CC_COMPAT="${TOOL_CROSS_COMPILE_COMPAT}gcc"
    LLVM=1
    LLVM_IAS=1
    BRANCH="${KERNEL_BRANCH}"
    KMI_GENERATION="${KMI_GENERATION}"
    LOCALVERSION="${LOCALVERSION}"
    KBUILD_BUILD_USER="${KBUILD_BUILD_USER}"
    KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"
    -j"$(nproc --all)"
)

# Ensure LTO cache dir exists on RAM disk
mkdir -p "$LTO_CACHE_DIR"

# ThinLTO: wrap ld.lld to redirect cache to RAM disk
if [ "${ENABLE_LTO}" = "THIN" ]; then
    LD_WRAPPER="${KERNEL_SRC}/ld-wrapper"
    cat > "$LD_WRAPPER" << 'WRAPPER_EOF'
#!/usr/bin/env bash
exec ld.lld "$@" \
    --thinlto-cache-dir=/dev/shm/ldcache \
    --thinlto-jobs=$(( $(nproc --all) / 2 ))
WRAPPER_EOF
    chmod +x "$LD_WRAPPER"
    MAKE_ARGS+=(LD="$LD_WRAPPER" HOSTLD="$LD_WRAPPER")
    log "ThinLTO ld-wrapper enabled (cache: /dev/shm/ldcache) ✅"
fi

# Defconfig + patches
touch "${KERNEL_SRC}/.scmversion"

log "Generating defconfig..."
make "${MAKE_ARGS[@]}" "$DEFCONFIG" || error "Defconfig failed!"

log "Applying Luminaire configs..."
source "${LUMINAIRE_PATCH_DIR}/kernel/config/defconfig.sh"

log "Syncing config..."
make "${MAKE_ARGS[@]}" olddefconfig || error "olddefconfig failed!"

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

# Build
# Timestamp freezing via libfakestat/libfaketimeMT is disabled —
# the prebuilt .so files are not compatible with the GitHub Actions
# Ubuntu runner libc and cause segfaults in all spawned processes.
# ccache-ECS still provides significant cache improvement via
# CCACHE_IS_KERNEL_COMPILING=true and content-hash validation.
CC_ARG="${TOOL_CCACHE_WRAPPERS}/clang"

log "Building kernel..."
START_TIME=$(date +%s)

make "${MAKE_ARGS[@]}" CC="$CC_ARG" || error "Build failed!"

BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
log "Build completed in ${BUILD_SECONDS}s ✅"
echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
