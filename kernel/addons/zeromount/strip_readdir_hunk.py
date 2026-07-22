#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0


import sys


def strip_readdir_hunk(path):
    with open(path, "r", errors="replace") as f:
        lines = f.readlines()
    out = []
    skip = False
    for i, line in enumerate(lines):
        if line.startswith("--- a/fs/readdir.c"):
            skip = True
        if skip and i > 0 and line.startswith("--- a/") and "readdir.c" not in line:
            skip = False
        if not skip:
            out.append(line)
    if len(out) == len(lines):
        print(
            "[warn] strip_readdir_hunk: readdir.c section not found in patch — "
            "patch may have changed upstream; proceeding without strip"
        )
        sys.exit(0)
    with open(path, "w") as f:
        f.writelines(out)
    removed = len(lines) - len(out)
    print(f"[info] strip_readdir_hunk: stripped {removed} lines (readdir.c hunk) from patch ✅")
    sys.exit(0)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/patch>", file=sys.stderr)
        sys.exit(1)
    strip_readdir_hunk(sys.argv[1])


if __name__ == "__main__":
    main()
