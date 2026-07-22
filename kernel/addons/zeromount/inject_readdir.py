#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0


import sys

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"

INCLUDE_ANCHOR = "#include <asm/unaligned.h>"
INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif"
)


FDGET_ANCHOR = "f = fdget_pos(fd);"
FDGET_NEXT   = "if (!f.file)"

FDGET_INJECT = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tint initial_count = count;\n"
    "#endif\n"
    "\n"
)


ITERATE_ANCHOR = "error = iterate_dir(f.file, &buf.ctx);"
ITERATE_NEXT   = "if (error >= 0)"

ITERATE_INJECT_BEFORE = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (f.file->f_pos >= ZEROMOUNT_MAGIC_POS) {\n"
    "\t\terror = 0;\n"
    "\t\tgoto skip_real_iterate;\n"
    "\t}\n"
    "#endif\n"
    "\n"
)

ITERATE_INJECT_AFTER = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "skip_real_iterate:\n"
    "\tif (error >= 0 && !signal_pending(current)) {\n"
    "\t\tzeromount_inject_dents(f.file, (void __user **)&dirent, &count, &f.file->f_pos);\n"
    "\t\tif (count != initial_count)\n"
    "\t\t\terror = initial_count - count;\n"
    "\t\tgoto zm_out;\n"
    "\t}\n"
    "#endif\n"
)

ZM_OUT_ANCHOR  = "fdput_pos(f);"
ZM_OUT_INJECT  = "zm_out:\n"


def find_getdents_non_compat(lines):
    in_compat = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "#ifdef CONFIG_COMPAT":
            in_compat = True
        if stripped == "#endif" and in_compat:
            in_compat = False
        if not in_compat and "SYSCALL_DEFINE3(getdents," in line:
            return i
    return None


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/readdir.c>", file=sys.stderr)
        sys.exit(1)
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()
    if IDEMPOTENCY_MARKER in content:
        print("[info] fix_readdir: ZeroMount already injected — skipping ✅")
        sys.exit(0)
    lines = content.splitlines(keepends=True)
    include_idx = None
    for i, line in enumerate(lines):
        if line.strip() == INCLUDE_ANCHOR:
            include_idx = i
            break
    if include_idx is None:
        print(
            f"[error] fix_readdir: anchor '{INCLUDE_ANCHOR}' not found — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    lines.insert(include_idx + 1, INCLUDE_INJECT + "\n")
    getdents_idx = find_getdents_non_compat(lines)
    if getdents_idx is None:
        print(
            "[error] fix_readdir: non-compat SYSCALL_DEFINE3(getdents, ...) not found — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    SEARCH_WINDOW = 120
    window = lines[getdents_idx : getdents_idx + SEARCH_WINDOW]
    fdget_rel = None
    for j, line in enumerate(window):
        if FDGET_ANCHOR in line:
            if j + 1 < len(window) and FDGET_NEXT in window[j + 1]:
                fdget_rel = j
                break
    if fdget_rel is None:
        print(
            f"[error] fix_readdir: fdget_pos anchor not found in getdents body — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    abs_fdget = getdents_idx + fdget_rel
    lines.insert(abs_fdget, FDGET_INJECT)
    window = lines[getdents_idx : getdents_idx + SEARCH_WINDOW]
    iterate_rel = None
    for j, line in enumerate(window):
        if ITERATE_ANCHOR in line:
            if j + 1 < len(window) and ITERATE_NEXT in window[j + 1]:
                iterate_rel = j
                break
    if iterate_rel is None:
        print(
            f"[error] fix_readdir: iterate_dir anchor not found in getdents body — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    abs_iterate = getdents_idx + iterate_rel
    lines.insert(abs_iterate, ITERATE_INJECT_BEFORE)
    abs_iterate_after = abs_iterate + 2
    lines.insert(abs_iterate_after, ITERATE_INJECT_AFTER)
    window = lines[getdents_idx : getdents_idx + SEARCH_WINDOW]
    zmout_rel = None
    for j, line in enumerate(window):
        if ZM_OUT_ANCHOR in line:
            zmout_rel = j
            break
    if zmout_rel is None:
        print(
            f"[error] fix_readdir: fdput_pos anchor not found in getdents body — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    abs_zmout = getdents_idx + zmout_rel
    lines.insert(abs_zmout, ZM_OUT_INJECT)
    with open(path, "w") as f:
        f.writelines(lines)
    print("[info] fix_readdir: ZeroMount injected into readdir.c ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
