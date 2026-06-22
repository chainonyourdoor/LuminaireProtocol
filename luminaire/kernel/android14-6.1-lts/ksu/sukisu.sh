#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — SukiSU-Ultra (android14-6.1-lts)
# ======================================================

KSU_DIR="${KERNEL_SRC}/KernelSU"

# ======================================================
# 1. SukiSU-Ultra
# ======================================================

log "Integrating SukiSU-Ultra..."
cd "$KERNEL_SRC"
SUKISU_SETUP=$(curl -LSs --fail --retry 3 \
    "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh") \
    || error "SukiSU-Ultra: failed to download setup.sh!"
echo "$SUKISU_SETUP" | bash -s main || error "SukiSU-Ultra: setup.sh failed!"
[ -d "${KERNEL_SRC}/KernelSU" ] || error "SukiSU-Ultra: KernelSU dir not found after setup!"
cd "$ROOT_DIR"
log "SukiSU-Ultra integrated ✅"

# ======================================================
# 2. Branding
# ======================================================

log "Applying Luminaire branding..."
python3 - "${KSU_DIR}/kernel/Kbuild" << 'PYEOF'
import sys

with open(sys.argv[1]) as f:
    content = f.read()

old1 = ('KSU_VERSION_FULL := $(if $(call git_short_sha),v$(VERSION_TAG)-$(call git_short_sha)'
        '@$(call git_branch),v$(VERSION_TAG)-$(REPO_NAME)-unknown@unknown)')
new1 = (old1 + '\n'
        'KSU_VERSION_FULL := $(KSU_VERSION_FULL) Luminaire')

old2 = 'ccflags-y += -DKSU_VERSION_FULL=\\\"$(KSU_VERSION_FULL)\\\"'
new2 = "ccflags-y += -DKSU_VERSION_FULL='\"$(KSU_VERSION_FULL)\"'"

if "Luminaire" in content:
    print("Branding already applied, skipping.")
    sys.exit(0)

if old1 not in content:
    print("ERROR: VERSION_FULL line not found!", file=sys.stderr)
    sys.exit(1)

if old2 not in content:
    print("ERROR: ccflags VERSION_FULL line not found!", file=sys.stderr)
    sys.exit(1)

content = content.replace(old1, new1).replace(old2, new2)

with open(sys.argv[1], 'w') as f:
    f.write(content)

print("Branding injected successfully.")
PYEOF
log "Branding applied ✅"

# ======================================================
# 3. SuSFS Hook Bridge
# ======================================================
# syscall_hooks.patch injects ksu_handle_*() call points into
# vanilla kernel syscall paths (fs/exec.c, fs/open.c, fs/stat.c,
# etc.) — bridging SukiSU-Ultra's syscall_hook_manager architecture
# to the classic inline-hook API expected by susfs4ksu patches.
# Must be applied BEFORE susfs.sh runs.

SUKISU_PATCH_REPO="https://github.com/ShirkNeko/SukiSU_patch.git"
SUKISU_PATCH_DIR="/tmp/sukisu_patch"

log "Cloning SukiSU_patch (hook bridge)..."
[ -d "$SUKISU_PATCH_DIR" ] && rm -rf "$SUKISU_PATCH_DIR"
retry 3 run_quiet git clone -q --depth=1 "$SUKISU_PATCH_REPO" "$SUKISU_PATCH_DIR" \
    || error "SukiSU_patch: failed to clone!"

HOOK_PATCH="${SUKISU_PATCH_DIR}/hooks/syscall_hooks.patch"
if [ -f "$HOOK_PATCH" ]; then
    if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$HOOK_PATCH" > /dev/null 2>&1; then
        log "syscall_hooks already applied, skipping."
    else
        patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$HOOK_PATCH" \
            && log "syscall_hooks patch applied ✅" \
            || warn "syscall_hooks: some hunks failed — SuSFS integration may be degraded"
    fi
else
    warn "syscall_hooks.patch not found in SukiSU_patch repo"
fi
rm -rf "$SUKISU_PATCH_DIR"

# ======================================================
# 4. Kconfig
# ======================================================

log "Enabling KSU configs..."
cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
log "Configs enabled ✅"

log "SukiSU-Ultra ready ✅"
