import sys

# Fixes a mis-landed SUSFS patch hunk in show_smap()/task_mmu.c. See CODEX.md.

SUS_MAP_GUARD = (
    "#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
    "\tif (vma->vm_file) {\n"
    "\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n"
    "\t\t\treturn 0;\n"
    "\t}\n"
    "#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
)

BROKEN_BLOCK = (
    '\tSEQ_PUT_DEC(" kB\\nSwapPss:        ",\n'
    + SUS_MAP_GUARD
    + "\n"
    + "\t\t\t\t\tmss->swap_pss >> PSS_SHIFT);"
)

FIXED_BLOCK = (
    '\tSEQ_PUT_DEC(" kB\\nSwapPss:        ",\n'
    "\t\t\t\t\tmss->swap_pss >> PSS_SHIFT);"
)

SHOW_SMAP_ANCHOR = (
    "static int show_smap(struct seq_file *m, void *v)\n"
    "{\n"
    "\tstruct vm_area_struct *vma = v;\n"
    "\tstruct mem_size_stats mss = {};\n"
    "\n"
)


def main():
    path = sys.argv[1]
    with open(path) as f:
        content = f.read()

    if BROKEN_BLOCK not in content:
        if SUS_MAP_GUARD in content:
            print("task_mmu.c: SUS_MAP guard already present and not mis-landed, skipping.")
        else:
            print("task_mmu.c: mis-landed SUS_MAP guard not found (patch didn't apply this hunk, or upstream already fixed it), skipping.")
        sys.exit(0)

    if SHOW_SMAP_ANCHOR not in content:
        print("ERROR: show_smap() anchor not found — can't safely re-insert SUS_MAP guard!", file=sys.stderr)
        sys.exit(1)

    # Remove the mis-landed guard, restoring the original SEQ_PUT_DEC call.
    content = content.replace(BROKEN_BLOCK, FIXED_BLOCK, 1)

    # Re-insert it where it actually belongs: right after `mss = {};` in show_smap().
    content = content.replace(SHOW_SMAP_ANCHOR, SHOW_SMAP_ANCHOR + SUS_MAP_GUARD + "\n", 1)

    with open(path, "w") as f:
        f.write(content)
    print("task_mmu.c: relocated mis-landed SUS_MAP guard into show_smap() ✅")


if __name__ == "__main__":
    main()
