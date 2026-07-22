#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0


import sys


def strip_namei_hunk(path):
    with open(path, "r", errors="replace") as f:
        lines = f.readlines()
    out = []
    skip = False
    for i, line in enumerate(lines):
        if line.startswith("--- a/fs/namei.c"):
            skip = True
        if skip and i > 0 and line.startswith("--- a/") and "namei.c" not in line:
            skip = False
        if not skip:
            out.append(line)
    if len(out) == len(lines):
        print(
            "[warn] strip_namei_hunk: namei.c section not found in patch — "
            "patch may have changed upstream; proceeding without strip"
        )
        sys.exit(0)
    with open(path, "w") as f:
        f.writelines(out)
    removed = len(lines) - len(out)
    print(f"[info] strip_namei_hunk: stripped {removed} lines (namei.c hunk) from patch ✅")
    sys.exit(0)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/patch>", file=sys.stderr)
        sys.exit(1)
    strip_namei_hunk(sys.argv[1])


if __name__ == "__main__":
    main()
