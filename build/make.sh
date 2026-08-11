#!/usr/bin/env bash

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

mkdir -p "$LTO_CACHE_DIR"

LD_JOBS=$(( $(nproc --all) / 2 ))
[ "$LD_JOBS" -ge 1 ] || LD_JOBS=1

NEEDS_WRAPPER=0
if [ "${LTO_MODE}" = "THIN" ]; then
    NEEDS_WRAPPER=1
elif [ "${LTO_MODE}" = "NONE" ] && [[ "${KERNEL_VERSION}" == 5.* ]]; then
    NEEDS_WRAPPER=1
fi

if [ "$NEEDS_WRAPPER" = "1" ]; then
    LD_WRAPPER="${KERNEL_SRC}/ld-wrapper"
    {
        echo '#!/usr/bin/env bash'
        if [ "${LTO_MODE}" = "THIN" ]; then
            echo "exec ld.lld \"\$@\" --thinlto-cache-dir=/dev/shm/ldcache --thinlto-jobs=${LD_JOBS} --threads=${LD_JOBS}"
        else
            echo "exec ld.lld \"\$@\" --threads=1"
        fi
    } > "$LD_WRAPPER"
    chmod +x "$LD_WRAPPER"
    MAKE_ARGS+=(LD="$LD_WRAPPER" HOSTLD="$LD_WRAPPER")

    if [ "${LTO_MODE}" = "THIN" ]; then
        log "ThinLTO ld-wrapper enabled (cache: /dev/shm/ldcache, jobs/threads: ${LD_JOBS}) ✅"
    else
        log "ld-wrapper enabled: kernel ${KERNEL_VERSION} + LTO_MODE=NONE (threads: 1, memory-bounded link) ✅"
    fi
fi

touch "${KERNEL_SRC}/.scmversion"

log "Generating defconfig..."
make "${MAKE_ARGS[@]}" "$DEFCONFIG" || error "Defconfig failed!"

log "Applying Luminaire configs..."
source "${LUMINAIRE_PATCH_DIR}/kernel/config/defconfig.sh"

log "Syncing config..."
make "${MAKE_ARGS[@]}" olddefconfig || error "olddefconfig failed!"

log "Debug-info config (diagnosing link memory usage):"
grep -E "^CONFIG_DEBUG_INFO|^# CONFIG_DEBUG_INFO" "${OUT_DIR}/.config" | while read -r line; do
    log "  ${line}"
done

log "Applying version patches..."
for patch in "${PATCHES_DIR}/required/"*.patch; do
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

CC_ARG="${TOOL_CCACHE_WRAPPERS}/clang"

if [ "${DRY_RUN:-false}" = "true" ]; then
    write_dry_run_image "${OUT_DIR}/arch/${ARCH}/boot/Image"
    BUILD_SECONDS=0
else
    log "Building kernel..."
    START_TIME=$(date +%s)

    make "${MAKE_ARGS[@]}" CC="$CC_ARG" || error "Build failed!"

    BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
    log "Build completed in ${BUILD_SECONDS}s ✅"
fi
echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
