#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — ZeroMount (VFS path redirection engine)
# ======================================================
# Repo: https://github.com/Enginex0/zeromount
# Patch source: https://github.com/Enginex0/Super-Builders
# Note: self-contained patch (creates fs/zeromount.c,
#       include/linux/zeromount.h, Kconfig + Makefile wiring).
#       Directory-listing injection hunks anchor on
#       CONFIG_KSU_SUSFS_SUS_PATH context — best paired with
#       SuSFS. Falls back gracefully (warn+continue) without it.

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/60_zeromount-android14-6.1.patch"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/addons/zeromount"

log "Downloading ZeroMount kernel patch..."
retry 3 run_quiet curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount patch download failed — skipping"; return 0; }

log "Applying ZeroMount kernel patch..."
# readdir.c hunks require SuSFS context to apply cleanly.
# Without SuSFS, failed hunks cause patch to corrupt readdir.c
# with content from other files (Makefile/Kconfig fragments).
# Save it before patching and restore after.
READDIR_BACKUP="/tmp/readdir.c.zeromount.bak"
cp "${KERNEL_SRC}/fs/readdir.c" "$READDIR_BACKUP"

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /dev/null 2>&1; then
    log "ZeroMount patch already applied, skipping."
    rm -f "$READDIR_BACKUP"
else
    if patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /tmp/zm_patch.log 2>&1; then
        log "ZeroMount patch applied ✅"
        rm -f "$READDIR_BACKUP" /tmp/zm_patch.log
    else
        warn "ZeroMount patch: some hunks failed — restoring readdir.c to prevent corruption"
        cp "$READDIR_BACKUP" "${KERNEL_SRC}/fs/readdir.c"
        rm -f "$READDIR_BACKUP" /tmp/zm_patch.log
    fi
fi

rm -f "$ZEROMOUNT_PATCH"

# Guard: verify zeromount was actually injected before running fix scripts.
# If the patch failed entirely, zeromount markers won't be present — skip
# fixes and warn rather than silently reporting success.
if ! grep -qF "zeromount" "${KERNEL_SRC}/fs/namei.c"; then
    warn "ZeroMount: no zeromount markers found in namei.c — patch may have failed entirely, skipping fix scripts"
    warn "ZeroMount integration incomplete — kernel will build without ZeroMount"
    return 0
fi

log "Fixing namei.c scope issues (zeromount blocks in wrong positions)..."
python3 "${PATCHER_DIR}/fix_namei.py" "${KERNEL_SRC}/fs/namei.c" \
    || error "ZeroMount: namei.c fix failed!"
log "namei.c fixed ✅"

log "Fixing task_mmu.c scope issue (zeromount call outside inode scope)..."
python3 "${PATCHER_DIR}/fix_taskmmu.py" "${KERNEL_SRC}/fs/proc/task_mmu.c" \
    || error "ZeroMount: task_mmu.c fix failed!"
log "task_mmu.c fixed ✅"

log "ZeroMount integrated ✅"
