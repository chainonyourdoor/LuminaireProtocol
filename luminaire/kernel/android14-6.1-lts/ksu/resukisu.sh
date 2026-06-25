#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — ReSukiSU (android14-6.1-lts)
# ======================================================

KSU_DIR="${KERNEL_SRC}/KernelSU"

# ======================================================
# 1. ReSukiSU
# ======================================================

log "Integrating ReSukiSU..."
cd "$KERNEL_SRC"
RESUKISU_SETUP=$(curl -LSs --fail --retry 3 \
    "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh") \
    || error "ReSukiSU: failed to download setup.sh!"
[ -n "$RESUKISU_SETUP" ] || error "ReSukiSU: setup.sh is empty!"
echo "$RESUKISU_SETUP" | grep -q "^#!" || error "ReSukiSU: setup.sh looks invalid (no shebang)!"
echo "$RESUKISU_SETUP" | bash || error "ReSukiSU: setup.sh failed!"
[ -d "${KERNEL_SRC}/KernelSU" ] || error "ReSukiSU: KernelSU dir not found after setup!"
cd "$ROOT_DIR"
log "ReSukiSU integrated ✅"

# ======================================================
# 2. Branding
# ======================================================

log "Applying Luminaire branding..."
python3 - "${KSU_DIR}/kernel/Kbuild" << 'PYEOF'
import sys

with open(sys.argv[1]) as f:
    content = f.read()

old1 = 'KSU_VERSION_FULL := $(subst %KSU_VERSION%,$(KSU_VERSION),$(KSU_VERSION_FULL))'
new1 = ('KSU_VERSION_FULL := $(subst %KSU_VERSION%,$(KSU_VERSION),$(KSU_VERSION_FULL))\n'
        'KSU_VERSION_FULL := $(KSU_TAG_NAME) Luminaire')

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
# 3. Multi-Manager
# ======================================================

log "Patching multi-manager support..."
python3 - "${KSU_DIR}/kernel/manager/manager_sign.h" "${KSU_DIR}/kernel/manager/apk_sign.c" << 'PYEOF'
import sys

with open(sys.argv[1]) as f:
    content = f.read()

old_sign = ('// KOWX712/KernelSU\n'
            '#define EXPECTED_SIZE_KOWX712 0x375\n'
            '#define EXPECTED_HASH_KOWX712 "484fcba6e6c43b1fb09700633bf2fb4758f13cb0b2f4457b80d075084b26c588"')

new_sign = ('// KOWX712/KernelSU\n'
            '#define EXPECTED_SIZE_KOWX712 0x375\n'
            '#define EXPECTED_HASH_KOWX712 "484fcba6e6c43b1fb09700633bf2fb4758f13cb0b2f4457b80d075084b26c588"\n'
            '\n'
            '// rifsxd/KernelSU-Next\n'
            '#define EXPECTED_SIZE_KSUNEXT 0x3e6\n'
            '#define EXPECTED_HASH_KSUNEXT "79e590113c4c4c0c222978e413a5faa801666957b1212a328e46c00c69821bf7"\n'
            '\n'
            '// rapli/MamboSU\n'
            '#define EXPECTED_SIZE_MAMBOSU 0x384\n'
            '#define EXPECTED_HASH_MAMBOSU "a9462b8b98ea1ca7901b0cbdcebfaa35f0aa95e51b01d66e6b6d2c81b97746d8"\n'
            '\n'
            '// vortexsu/VortexSU\n'
            '#define EXPECTED_SIZE_VORTEXSU 0x381\n'
            '#define EXPECTED_HASH_VORTEXSU "67eec44718428adad14e6a9dca57822759aba7e77a8cad7071f6f6704df8bb48"\n'
            '\n'
            '// twj/WildKSU\n'
            '#define EXPECTED_SIZE_WILDKSU 0x381\n'
            '#define EXPECTED_HASH_WILDKSU "52d52d8c8bfbe53dc2b6ff1c613184e2c03013e090fe8905d8e3d5dc2658c2e4"')

if "EXPECTED_SIZE_KSUNEXT" in content:
    print("manager_sign.h already patched, skipping.")
else:
    if old_sign not in content:
        print("ERROR: target block not found in manager_sign.h!", file=sys.stderr)
        sys.exit(1)
    content = content.replace(old_sign, new_sign)
    with open(sys.argv[1], 'w') as f:
        f.write(content)
    print("manager_sign.h patched.")

with open(sys.argv[2]) as f:
    content = f.read()

old_apk = ('    { EXPECTED_SIZE_KOWX712, EXPECTED_HASH_KOWX712 }, // KOWX712/KernelSU\n'
           '#ifdef EXPECTED_SIZE')

new_apk = ('    { EXPECTED_SIZE_KOWX712, EXPECTED_HASH_KOWX712 }, // KOWX712/KernelSU\n'
           '    { EXPECTED_SIZE_KSUNEXT, EXPECTED_HASH_KSUNEXT }, // rifsxd/KernelSU-Next\n'
           '    { EXPECTED_SIZE_MAMBOSU, EXPECTED_HASH_MAMBOSU }, // rapli/MamboSU\n'
           '    { EXPECTED_SIZE_VORTEXSU, EXPECTED_HASH_VORTEXSU }, // vortexsu/VortexSU\n'
           '    { EXPECTED_SIZE_WILDKSU, EXPECTED_HASH_WILDKSU }, // twj/WildKSU\n'
           '#ifdef EXPECTED_SIZE')

if "EXPECTED_SIZE_KSUNEXT" in content:
    print("apk_sign.c already patched, skipping.")
else:
    if old_apk not in content:
        print("ERROR: target block not found in apk_sign.c!", file=sys.stderr)
        sys.exit(1)
    content = content.replace(old_apk, new_apk)
    with open(sys.argv[2], 'w') as f:
        f.write(content)
    print("apk_sign.c patched.")
PYEOF
log "Multi-manager patched ✅"

# ======================================================
# 4. KSU-Next compat
# ======================================================

log "Patching KSU-Next manager compat..."
python3 - "${KSU_DIR}/kernel/supercall/dispatch.c" << 'PYEOF'
import sys

with open(sys.argv[1]) as f:
    content = f.read()

old_funcs = '// 101. HOOK_TYPE - Get hook type'

new_funcs = '''// KSU-Next compat: GET_VERSION_TAG (IOCTL 99)
static int do_ksunext_compat_version_tag(void __user *arg)
{
    struct {
        char tag[32];
    } cmd = { 0 };

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0)
    strscpy(cmd.tag, KSU_VERSION_FULL, sizeof(cmd.tag));
#else
    strlcpy(cmd.tag, KSU_VERSION_FULL, sizeof(cmd.tag));
#endif

    if (copy_to_user(arg, &cmd, sizeof(cmd))) {
        pr_err("ksunext_compat_version_tag: copy_to_user failed\\n");
        return -EFAULT;
    }

    return 0;
}

// KSU-Next compat: GET_HOOK_MODE (IOCTL 98)
static int do_ksunext_compat_hook_mode(void __user *arg)
{
    struct {
        char mode[16];
    } cmd = { 0 };

#if defined(CONFIG_KSU_TRACEPOINT_HOOK)
    const char *mode = "Tracepoint";
#elif defined(CONFIG_KSU_MANUAL_HOOK)
    const char *mode = "Manual";
#elif defined(CONFIG_KSU_SUSFS)
    const char *mode = "Inline (SusFS)";
#else
    const char *mode = "Unknown";
#endif

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0)
    strscpy(cmd.mode, mode, sizeof(cmd.mode));
#else
    strlcpy(cmd.mode, mode, sizeof(cmd.mode));
#endif

    if (copy_to_user(arg, &cmd, sizeof(cmd))) {
        pr_err("ksunext_compat_hook_mode: copy_to_user failed\\n");
        return -EFAULT;
    }

    return 0;
}

// 101. HOOK_TYPE - Get hook type'''

old_table = '    // downstream begin'
new_table = '''    // KSU-Next manager compat
    {
        .cmd = _IOC(_IOC_READ, 'K', 98, 0),
        .name = "GET_HOOK_MODE_COMPAT",
        .handler = do_ksunext_compat_hook_mode,
        .perm_check = always_allow
    },
    {
        .cmd = _IOC(_IOC_READ, 'K', 99, 0),
        .name = "GET_VERSION_TAG_COMPAT",
        .handler = do_ksunext_compat_version_tag,
        .perm_check = always_allow
    },
    // downstream begin'''

if "ksunext_compat" in content:
    print("dispatch.c already patched, skipping.")
    sys.exit(0)

if old_funcs not in content:
    print("ERROR: function target not found!", file=sys.stderr)
    sys.exit(1)

if old_table not in content:
    print("ERROR: table target not found!", file=sys.stderr)
    sys.exit(1)

content = content.replace(old_funcs, new_funcs)
content = content.replace(old_table, new_table)

with open(sys.argv[1], 'w') as f:
    f.write(content)

print("KSU-Next compat patch applied.")
PYEOF
log "KSU-Next compat patched ✅"

# ======================================================
# 5. Kconfig
# ======================================================

log "Enabling KSU configs..."
cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
log "Configs enabled ✅"

log "ReSukiSU ready ✅"
