import sys


def main():
    path = sys.argv[1]
    with open(path) as f:
        content = f.read()
    broken = (
        '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t}\n'
        '\n'
        '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        'orig_flow:\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
    )
    fixed = (
        '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        '\t}\n'
        '\n'
        '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
        'orig_flow:\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
    )
    if broken in content:
        content = content.replace(broken, fixed)
        with open(path, 'w') as f:
            f.write(content)
        print("task_mmu.c scope fix applied.")
        sys.exit(0)
    if "zeromount_spoof_mmap_metadata" not in content:
        print("ERROR: zeromount call not found in task_mmu.c — ZeroMount patch/injection "
              "may not have run yet, or upstream task_mmu.c structure changed!", file=sys.stderr)
        sys.exit(1)
    print("Pattern already fixed or different, skipping.")


if __name__ == "__main__":
    main()
