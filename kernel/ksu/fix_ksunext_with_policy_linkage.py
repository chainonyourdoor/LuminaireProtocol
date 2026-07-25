import sys

# pershoot/KernelSU-Next@dev-susfs's kernel/feature/selinux_hide.c forward-declares
# security_context_to_sid_with_policy / security_sid_to_context_with_policy /
# security_compute_av_user_with_policy as `static` under
# "#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 6, 0)", even though the actual
# definitions further down the file omit `static`. In C, linkage is fixed by the
# first declaration seen in the translation unit, so these stay internal-linkage
# for the whole file regardless of the later definitions. security/selinux/hooks.c
# and selinuxfs.c (patched in by susfs4ksu's kernel patch) call these via `extern`,
# expecting external linkage, so the link fails with "undefined symbol" on kernel
# >= 6.6 (android15-6.6, android16-6.12). Kernels < 6.6 take a different `#else`
# branch in that file and never hit this.
#
# susfs4ksu ships a real fix for this in kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch,
# but that patch targets vanilla KernelSU-Next and fails most of its hunks against
# this already-mostly-patched fork. Rather than force that patch, just fix the 3
# forward declarations directly.

TARGETS = [
    (
        "static int security_context_to_sid_with_policy(struct selinux_policy *policy, "
        "const char *scontext, u32 scontext_len,",
        "int security_context_to_sid_with_policy(struct selinux_policy *policy, "
        "const char *scontext, u32 scontext_len,",
    ),
    (
        "static int security_sid_to_context_with_policy(struct selinux_policy *policy, "
        "u32 sid, char **scontext,",
        "int security_sid_to_context_with_policy(struct selinux_policy *policy, "
        "u32 sid, char **scontext,",
    ),
    (
        "static void security_compute_av_user_with_policy(struct selinux_policy *policy, "
        "u32 ssid, u32 tsid, u16 tclass,",
        "void security_compute_av_user_with_policy(struct selinux_policy *policy, "
        "u32 ssid, u32 tsid, u16 tclass,",
    ),
]


def main():
    path = sys.argv[1]
    with open(path) as f:
        content = f.read()

    present = [old for old, _ in TARGETS if old in content]

    if not present:
        print(
            "selinux_hide.c: no `static` with_policy forward-declarations found "
            "(already fixed, or fork source changed upstream) — skipping."
        )
        sys.exit(0)

    for old, new in TARGETS:
        if old in content:
            content = content.replace(old, new, 1)

    with open(path, "w") as f:
        f.write(content)

    print("Fixed static/extern linkage mismatch for security_*_with_policy in selinux_hide.c ✅")


if __name__ == "__main__":
    main()
