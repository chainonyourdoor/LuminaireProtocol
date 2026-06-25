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
[ -n "$SUKISU_SETUP" ] || error "SukiSU-Ultra: setup.sh is empty!"
echo "$SUKISU_SETUP" | grep -q "^#!" || error "SukiSU-Ultra: setup.sh looks invalid (no shebang)!"
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
# 3. Kconfig
# ======================================================

log "Enabling KSU configs..."
cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
log "Configs enabled ✅"

log "SukiSU-Ultra ready ✅"
