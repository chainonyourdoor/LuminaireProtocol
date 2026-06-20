#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS — shared apply logic (any KSU fork, android14-6.1-lts)
# ======================================================

SUSFS_BRANCH="gki-android14-6.1"
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_DIR="/tmp/susfs4ksu"

log "Cloning SuSFS (${SUSFS_BRANCH})..."
[ -d "$SUSFS_DIR" ] && rm -rf "$SUSFS_DIR"
retry 3 run_quiet git clone -q --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
    || error "SuSFS clone failed after 3 attempts!"

log "Copying SuSFS source files..."
cp "${SUSFS_DIR}/kernel_patches/fs/susfs.c"                  "${KERNEL_SRC}/fs/susfs.c"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs.h"       "${KERNEL_SRC}/include/linux/susfs.h"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs_def.h"   "${KERNEL_SRC}/include/linux/susfs_def.h"
log "SuSFS source files copied ✅"

log "Applying SuSFS kernel patch..."
KERNEL_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"
[ -f "$KERNEL_PATCH" ] || { warn "SuSFS kernel patch not found — skipping"; return 0; }
if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KERNEL_PATCH" > /dev/null 2>&1; then
    log "SuSFS kernel patch already applied, skipping."
else
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$KERNEL_PATCH" \
        && log "SuSFS kernel patch applied ✅" \
        || warn "SuSFS kernel patch: some hunks failed — continuing"
fi

log "Fixing namespace.c susfs declarations..."
python3 - "${KERNEL_SRC}/fs/namespace.c" << 'PYEOF'
import sys

with open(sys.argv[1]) as f:
    content = f.read()

if "susfs_is_current_ksu_domain" in content and "susfs_def.h" in content:
    print("namespace.c already patched, skipping.")
    sys.exit(0)

include_target = "#include <linux/mnt_idmapping.h>"
include_inject = ("#include <linux/mnt_idmapping.h>\n"
                  "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
                  "#include <linux/susfs_def.h>\n"
                  "#endif")

internal_target = '#include "internal.h"'
internal_inject = ('#include "internal.h"\n'
                   "\n"
                   "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
                   "extern bool susfs_is_current_ksu_domain(void);\n"
                   "extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n"
                   "\n"
                   "#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */\n"
                   "#endif")

if include_target not in content:
    print("ERROR: mnt_idmapping.h include not found!", file=sys.stderr)
    sys.exit(1)

if internal_target not in content:
    print("ERROR: internal.h include not found!", file=sys.stderr)
    sys.exit(1)

content = content.replace(include_target, include_inject, 1)
content = content.replace(internal_target, internal_inject, 1)

with open(sys.argv[1], 'w') as f:
    f.write(content)

print("namespace.c patched successfully.")
PYEOF
log "namespace.c fixed ✅"

rm -rf "$SUSFS_DIR"

log "Enabling SuSFS configs..."
cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIGS
log "SuSFS configs enabled ✅"

log "SuSFS integrated ✅"
