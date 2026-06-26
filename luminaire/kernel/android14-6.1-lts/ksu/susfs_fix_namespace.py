import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
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

    with open(path, 'w') as f:
        f.write(content)

    print("namespace.c patched successfully.")


if __name__ == "__main__":
    main()
