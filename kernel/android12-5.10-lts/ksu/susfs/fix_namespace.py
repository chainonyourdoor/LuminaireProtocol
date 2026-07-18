import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    if "susfs_is_current_ksu_domain" in content and "susfs_def.h" in content:
        # Both markers present — either the main patch applied hunk #1 successfully
        # (after blk.h pre-patch removal in susfs.sh), or a previous run of this
        # fallback already injected them. Either way, nothing left to do.
        print("namespace.c already patched, skipping.")
        sys.exit(0)

    # ── Injection 1: susfs_def.h include after mnt_idmapping.h ──
    include_target = "#include <linux/mnt_idmapping.h>"
    include_inject = (
        "#include <linux/mnt_idmapping.h>\n"
        "#if defined(CONFIG_KSU_SUSFS_SUS_MOUNT) || defined(CONFIG_KSU_SUSFS_TRY_UMOUNT)\n"
        "#include <linux/susfs_def.h>\n"
        "#endif"
    )

    # ── Injection 2: extern declarations after internal.h ──
    internal_target = '#include "internal.h"'
    internal_inject = (
        '#include "internal.h"\n'
        "\n"
        "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
        "extern bool susfs_is_current_ksu_domain(void);\n"
        "extern bool susfs_is_current_zygote_domain(void);\n"
        "extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n"
        "\n"
        "static DEFINE_IDA(susfs_mnt_id_ida);\n"
        "static DEFINE_IDA(susfs_mnt_group_ida);\n"
        "\n"
        "#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */\n"
        "#endif\n"
        "\n"
        "#ifdef CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT\n"
        "extern void susfs_auto_add_sus_ksu_default_mount(const char __user *to_pathname);\n"
        "bool susfs_is_auto_add_sus_ksu_default_mount_enabled = true;\n"
        "#endif\n"
        "#ifdef CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT\n"
        "extern int susfs_auto_add_sus_bind_mount(const char *pathname, struct path *path_target);\n"
        "bool susfs_is_auto_add_sus_bind_mount_enabled = true;\n"
        "#endif\n"
        "#ifdef CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT\n"
        "extern void susfs_auto_add_try_umount_for_bind_mount(struct path *path);\n"
        "bool susfs_is_auto_add_try_umount_for_bind_mount_enabled = true;\n"
        "#endif"
    )

    if include_target not in content:
        print("ERROR: mnt_idmapping.h include not found!", file=sys.stderr)
        sys.exit(1)

    if internal_target not in content:
        print("ERROR: internal.h include not found!", file=sys.stderr)
        sys.exit(1)

    content = content.replace(include_target, include_inject, 1)
    content = content.replace(internal_target, internal_inject, 1)

    with open(path, "w") as f:
        f.write(content)

    print("namespace.c patched successfully.")


if __name__ == "__main__":
    main()
