import sys


KCONFIG_BLOCK = '''menu "KernelSU - SUSFS"
config KSU_SUSFS
\tbool "KernelSU addon - SUSFS"
\tdepends on KSU
\tdepends on THREAD_INFO_IN_TASK
\tdefault y
\thelp
\t  Patch and Enable SUSFS to kernel with KernelSU.

config KSU_SUSFS_SUS_PATH
\tbool "Enable to hide suspicious path"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow hiding the user-defined path and all its sub-paths from various system calls.

config KSU_SUSFS_SUS_MOUNT
\tbool "Enable to hide suspicious mounts"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow hiding all sus mounts from /proc/self/[mounts|mountinfo|mountstat] for non-su processes.

config KSU_SUSFS_SUS_KSTAT
\tbool "Enable to spoof suspicious kstat"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow spoofing the kstat of user-defined file/directory.

config KSU_SUSFS_SUS_OVERLAYFS
\tbool "Enable to hide suspicious overlayfs"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow hiding suspicious overlayfs mounts from various system calls.

config KSU_SUSFS_TRY_UMOUNT
\tbool "Enable to use umount to hide suspicious mounts"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow using umount to hide suspicious mounts from processes.

config KSU_SUSFS_SUS_SU
\tbool "Enable to disable kprobe su as sus_su"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow disabling kprobe based ksu su and using sus_su instead.

config KSU_SUSFS_SPOOF_UNAME
\tbool "Enable to spoof uname"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow spoofing the string returned by uname syscall.

config KSU_SUSFS_ENABLE_LOG
\tbool "Enable logging susfs log to kernel"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow logging susfs log to kernel.

config KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
\tbool "Enable to automatically hide ksu and susfs symbols from /proc/kallsyms"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Automatically hide ksu and susfs symbols from /proc/kallsyms.

config KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
\tbool "Enable to spoof /proc/bootconfig or /proc/cmdline"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Spoof the output of /proc/bootconfig (gki) or /proc/cmdline (non-gki).

config KSU_SUSFS_OPEN_REDIRECT
\tbool "Enable to redirect a path to be opened with another path"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow redirecting a target path to be opened with another user-defined path.

config KSU_SUSFS_SUS_MAP
\tbool "Enable to hide some mmapped real file from different proc maps interfaces"
\tdepends on KSU_SUSFS
\tdefault y
\thelp
\t  Allow hiding mmapped real file from /proc/<pid>/[maps|smaps|smaps_rollup|map_files|mem|pagemap].

endmenu'''


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    if "config KSU_SUSFS" in content:
        print("KSU_SUSFS Kconfig already present, skipping.")
        sys.exit(0)

    new_content = content.rstrip() + "\n\n" + KCONFIG_BLOCK + "\n"

    with open(path, 'w') as f:
        f.write(new_content)

    print("KSU_SUSFS Kconfig block appended.")


if __name__ == "__main__":
    main()
