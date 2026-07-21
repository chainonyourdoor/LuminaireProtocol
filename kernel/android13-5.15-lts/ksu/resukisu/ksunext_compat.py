import sys


NEW_FUNCS = '''\
// KSU-Next compat: GET_VERSION_TAG (IOCTL 99)
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
    const char *mode = "Inline (SuSFS)";
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

NEW_TABLE = '''\
    // KSU-Next manager compat
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


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    if "ksunext_compat" in content:
        print("dispatch.c already patched, skipping.")
        sys.exit(0)

    old_funcs = '// 101. HOOK_TYPE - Get hook type'
    old_table = '    // downstream begin'

    if old_funcs not in content:
        print("ERROR: function target not found!", file=sys.stderr)
        sys.exit(1)

    if old_table not in content:
        print("ERROR: table target not found!", file=sys.stderr)
        sys.exit(1)

    content = content.replace(old_funcs, NEW_FUNCS)
    content = content.replace(old_table, NEW_TABLE)

    with open(path, 'w') as f:
        f.write(content)

    print("KSU-Next compat patch applied.")


if __name__ == "__main__":
    main()
