#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0


import sys

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"


INCLUDE_ANCHOR = '#include "mount.h"'
INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif"
)


GETNAME_ANCHOR = (
    "\tresult->uptr = filename;\n"
    "\tresult->aname = NULL;\n"
    "\taudit_getname(result);\n"
)
GETNAME_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (!IS_ERR(result)) {\n"
    "\t\tresult = zeromount_getname_hook(result);\n"
    "\t}\n"
    "#endif\n"
)


PERMISSION_INJECT = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (zeromount_is_injected_file(inode)) {\n"
    "\t\tif (mask & MAY_WRITE)\n"
    "\t\t\treturn -EACCES;\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "\n"
    "\tif (S_ISDIR(inode->i_mode) && zeromount_is_traversal_allowed(inode, mask)) {\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "#endif\n"
    "\n"
)

GENERIC_PERMISSION_ANCHOR = "\tret = acl_permission_check(mnt_userns, inode, mask);\n"
INODE_PERMISSION_ANCHOR = "\tretval = sb_permission(inode->i_sb, inode, mask);\n"


def find_anchor(lines, anchor, label):
    for i, line in enumerate(lines):
        if line == anchor:
            return i
    print(
        f"[error] inject_namei: anchor for {label} not found — "
        "upstream namei.c may have changed!",
        file=sys.stderr,
    )
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/namei.c>", file=sys.stderr)
        sys.exit(1)
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()
    if IDEMPOTENCY_MARKER in content:
        print("[info] inject_namei: ZeroMount already injected — skipping ✅")
        sys.exit(0)
    lines = content.splitlines(keepends=True)
    include_idx = find_anchor(lines, INCLUDE_ANCHOR + "\n", "#include \"mount.h\"")
    lines.insert(include_idx + 1, INCLUDE_INJECT + "\n")
    content = "".join(lines)
    lines = content.splitlines(keepends=True)
    content = "".join(lines)
    if GETNAME_ANCHOR not in content:
        print(
            "[error] inject_namei: getname_flags() anchor not found — "
            "upstream namei.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    content = content.replace(GETNAME_ANCHOR, GETNAME_ANCHOR + GETNAME_INJECT, 1)
    if GENERIC_PERMISSION_ANCHOR not in content:
        print(
            "[error] inject_namei: generic_permission() anchor not found — "
            "upstream namei.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    content = content.replace(
        GENERIC_PERMISSION_ANCHOR, PERMISSION_INJECT + GENERIC_PERMISSION_ANCHOR, 1
    )
    if INODE_PERMISSION_ANCHOR not in content:
        print(
            "[error] inject_namei: inode_permission() anchor not found — "
            "upstream namei.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    content = content.replace(
        INODE_PERMISSION_ANCHOR, PERMISSION_INJECT + INODE_PERMISSION_ANCHOR, 1
    )
    with open(path, "w") as f:
        f.write(content)
    print("[info] inject_namei: ZeroMount injected into namei.c ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
