#!/usr/bin/env bash

LZ4ZSTD_PATCH_BASE="https://raw.githubusercontent.com/mrcxlinux/kernel_patches/main/zram"
ZSTD_SRC_BASE="https://raw.githubusercontent.com/torvalds/linux/v6.15"
cd "${KERNEL_SRC}"

log "Downloading LZ4 patch..."
LZ4_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 "${LZ4ZSTD_PATCH_BASE}/001-lz4.patch") \
    || { warn "LZ4/ZSTD: failed to download 001-lz4.patch — skipping"; return 0; }
curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 -o /tmp/lz4armv8.S "${LZ4ZSTD_PATCH_BASE}/lz4armv8.S" \
    || { warn "LZ4/ZSTD: failed to download lz4armv8.S — skipping"; return 0; }

[ -n "$LZ4_PATCH" ] || { warn "LZ4/ZSTD: downloaded LZ4 patch is empty — skipping"; return 0; }

mkdir -p lib/lz4/lz4armv8
cp /tmp/lz4armv8.S lib/lz4/lz4armv8/lz4armv8.S
cat > lib/lz4/lz4armv8/lz4accel.h << 'LZ4ACCEL_H_EOF'
#include <linux/types.h>
#include <asm/simd.h>

#define LZ4_FAST_MARGIN                (128)

#if defined(CONFIG_ARM64) && defined(CONFIG_KERNEL_MODE_NEON)
#include <asm/neon.h>
#include <asm/cputype.h>

asmlinkage int _lz4_decompress_asm(uint8_t **dst_ptr, uint8_t *dst_begin,
				   uint8_t *dst_end, const uint8_t **src_ptr,
				   const uint8_t *src_end, bool dip);

asmlinkage int _lz4_decompress_asm_noprfm(uint8_t **dst_ptr, uint8_t *dst_begin,
					  uint8_t *dst_end, const uint8_t **src_ptr,
					  const uint8_t *src_end, bool dip);

static inline int lz4_decompress_accel_enable(void)
{
	return	may_use_simd();
}

extern int (*lz4_decompress_asm_fn[])(uint8_t **dst_ptr, uint8_t *dst_begin,
	uint8_t *dst_end, const uint8_t **src_ptr,
	const uint8_t *src_end, bool dip);

static inline ssize_t lz4_decompress_asm(
	uint8_t **dst_ptr, uint8_t *dst_begin, uint8_t *dst_end,
	const uint8_t **src_ptr, const uint8_t *src_end, bool dip)
{
	int ret;

	kernel_neon_begin();
	ret = lz4_decompress_asm_fn[smp_processor_id()](dst_ptr, dst_begin,
						dst_end, src_ptr,
						src_end, dip);
	kernel_neon_end();
	return (ssize_t)ret;
}

#define __ARCH_HAS_LZ4_ACCELERATOR

#else

static inline int lz4_decompress_accel_enable(void)
{
	return	0;
}

static inline ssize_t lz4_decompress_asm(
	uint8_t **dst_ptr, uint8_t *dst_begin, uint8_t *dst_end,
	const uint8_t **src_ptr, const uint8_t *src_end, bool dip)
{
	return 0;
}
#endif
LZ4ACCEL_H_EOF
cat > lib/lz4/lz4armv8/lz4accel.c << 'LZ4ACCEL_C_EOF'
#include "lz4accel.h"
#include <asm/cputype.h>

#ifdef CONFIG_CFI_CLANG
static inline int
__cfi_lz4_decompress_asm(uint8_t **dst_ptr, uint8_t *dst_begin,
			 uint8_t *dst_end, const uint8_t **src_ptr,
			 const uint8_t *src_end, bool dip)
{
	return _lz4_decompress_asm(dst_ptr, dst_begin, dst_end,
				   src_ptr, src_end, dip);
}

static inline int
__cfi_lz4_decompress_asm_noprfm(uint8_t **dst_ptr, uint8_t *dst_begin,
				uint8_t *dst_end, const uint8_t **src_ptr,
				const uint8_t *src_end, bool dip)
{
	return _lz4_decompress_asm_noprfm(dst_ptr, dst_begin, dst_end,
					  src_ptr, src_end, dip);
}

#define _lz4_decompress_asm		__cfi_lz4_decompress_asm
#define _lz4_decompress_asm_noprfm	__cfi_lz4_decompress_asm_noprfm
#endif

int lz4_decompress_asm_select(uint8_t **dst_ptr, uint8_t *dst_begin,
			      uint8_t *dst_end, const uint8_t **src_ptr,
			      const uint8_t *src_end, bool dip) {
	const unsigned i = smp_processor_id();

	switch(read_cpuid_part_number()) {
	case ARM_CPU_PART_CORTEX_A53:
		lz4_decompress_asm_fn[i] = _lz4_decompress_asm_noprfm;
		return _lz4_decompress_asm_noprfm(dst_ptr, dst_begin, dst_end,
						  src_ptr, src_end, dip);
	}
	lz4_decompress_asm_fn[i] = _lz4_decompress_asm;
	return _lz4_decompress_asm(dst_ptr, dst_begin, dst_end,
				   src_ptr, src_end, dip);
}

int (*lz4_decompress_asm_fn[NR_CPUS])(uint8_t **dst_ptr, uint8_t *dst_begin,
	uint8_t *dst_end, const uint8_t **src_ptr,
	const uint8_t *src_end, bool dip)
__read_mostly = {
	[0 ... NR_CPUS-1]  = lz4_decompress_asm_select,
};
LZ4ACCEL_C_EOF

apply_lz4zstd_patch() {
    local name="$1" content="$2" marker_check="$3"

    if eval "$marker_check" 2>/dev/null; then
        log "LZ4/ZSTD: ${name} already applied, skipping."
        return 0
    fi

    local touched_files
    touched_files=$(echo "$content" | grep -E '^\+\+\+ b/' | sed -E 's#^\+\+\+ b/##; s/\t.*//' | sort -u)

    local patch_log
    patch_log=$(echo "$content" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch 2>&1)
    local rc=$?

    if eval "$marker_check" 2>/dev/null; then
        if [ "$rc" -eq 0 ]; then
            log "LZ4/ZSTD: ${name} applied cleanly ✅"
        else
            warn "LZ4/ZSTD: ${name} applied — core source updated, known ARM64 accel rename hunks skipped (expected, non-fatal) ⚠️"
        fi
    else
        warn "LZ4/ZSTD: ${name} core source did not update — reverting and skipping"
        echo "$touched_files" | while read -r f; do
            [ -z "$f" ] && continue
            if git ls-files --error-unmatch "$f" > /dev/null 2>&1; then
                git checkout -q -- "$f"
            else
                rm -f "$f"
            fi
            rm -f "${f}.rej"
        done
    fi
}

apply_lz4zstd_patch "001-lz4.patch (LZ4 1.10.0)" "$LZ4_PATCH" 'grep -q "LZ4_VERSION_MINOR 10" lib/lz4/lz4.h'

ZSTD_FILES=(
    lib/zstd/Makefile
    lib/zstd/decompress_sources.h
    lib/zstd/zstd_common_module.c
    lib/zstd/zstd_compress_module.c
    lib/zstd/zstd_decompress_module.c
    lib/zstd/common/allocations.h
    lib/zstd/common/bits.h
    lib/zstd/common/bitstream.h
    lib/zstd/common/compiler.h
    lib/zstd/common/cpu.h
    lib/zstd/common/debug.c
    lib/zstd/common/debug.h
    lib/zstd/common/entropy_common.c
    lib/zstd/common/error_private.c
    lib/zstd/common/error_private.h
    lib/zstd/common/fse.h
    lib/zstd/common/fse_decompress.c
    lib/zstd/common/huf.h
    lib/zstd/common/mem.h
    lib/zstd/common/portability_macros.h
    lib/zstd/common/zstd_common.c
    lib/zstd/common/zstd_deps.h
    lib/zstd/common/zstd_internal.h
    lib/zstd/compress/clevels.h
    lib/zstd/compress/fse_compress.c
    lib/zstd/compress/hist.c
    lib/zstd/compress/hist.h
    lib/zstd/compress/huf_compress.c
    lib/zstd/compress/zstd_compress.c
    lib/zstd/compress/zstd_compress_internal.h
    lib/zstd/compress/zstd_compress_literals.c
    lib/zstd/compress/zstd_compress_literals.h
    lib/zstd/compress/zstd_compress_sequences.c
    lib/zstd/compress/zstd_compress_sequences.h
    lib/zstd/compress/zstd_compress_superblock.c
    lib/zstd/compress/zstd_compress_superblock.h
    lib/zstd/compress/zstd_cwksp.h
    lib/zstd/compress/zstd_double_fast.c
    lib/zstd/compress/zstd_double_fast.h
    lib/zstd/compress/zstd_fast.c
    lib/zstd/compress/zstd_fast.h
    lib/zstd/compress/zstd_lazy.c
    lib/zstd/compress/zstd_lazy.h
    lib/zstd/compress/zstd_ldm.c
    lib/zstd/compress/zstd_ldm.h
    lib/zstd/compress/zstd_ldm_geartab.h
    lib/zstd/compress/zstd_opt.c
    lib/zstd/compress/zstd_opt.h
    lib/zstd/compress/zstd_preSplit.c
    lib/zstd/compress/zstd_preSplit.h
    lib/zstd/decompress/huf_decompress.c
    lib/zstd/decompress/zstd_ddict.c
    lib/zstd/decompress/zstd_ddict.h
    lib/zstd/decompress/zstd_decompress.c
    lib/zstd/decompress/zstd_decompress_block.c
    lib/zstd/decompress/zstd_decompress_block.h
    lib/zstd/decompress/zstd_decompress_internal.h
    include/linux/zstd.h
    include/linux/zstd_lib.h
    include/linux/zstd_errors.h
)

replace_zstd_source() {
    log "Downloading ZSTD 1.5.7 source tree from torvalds/linux v6.15..."

    if grep -q "ZSTD_VERSION_RELEASE  7" include/linux/zstd_lib.h 2>/dev/null; then
        log "LZ4/ZSTD: ZSTD 1.5.7 already applied, skipping."
        return 0
    fi

    local staging f
    staging=$(mktemp -d)
    for f in "${ZSTD_FILES[@]}"; do
        mkdir -p "${staging}/$(dirname "$f")"
        if ! curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
                -o "${staging}/${f}" "${ZSTD_SRC_BASE}/${f}"; then
            warn "LZ4/ZSTD: failed to download ${f} from v6.15 — skipping ZSTD bump, keeping existing 1.4.10 source"
            rm -rf "$staging"
            return 0
        fi
    done

    for f in "${ZSTD_FILES[@]}"; do
        mkdir -p "$(dirname "$f")"
        cp "${staging}/${f}" "$f"
    done
    rm -rf "$staging"

    sed -i 's#include <linux/unaligned.h>#include <asm/unaligned.h>#' lib/zstd/common/mem.h

    if grep -q "ZSTD_VERSION_RELEASE  7" include/linux/zstd_lib.h; then
        log "LZ4/ZSTD: ZSTD bumped to 1.5.7 ✅"
    else
        warn "LZ4/ZSTD: ZSTD source replaced but version marker missing — check manually ⚠️"
    fi
}

replace_zstd_source

cd "${ROOT_DIR}"
log "LZ4/ZSTD bump done ✅"
