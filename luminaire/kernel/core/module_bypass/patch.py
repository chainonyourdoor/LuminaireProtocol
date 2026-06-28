import sys


def main():
    path = sys.argv[1]

    with open(path, "r") as f:
        lines = f.readlines()

    anchor = "bad_version:"
    anchor_idx = None
    for i, line in enumerate(lines):
        if anchor in line:
            anchor_idx = i
            break

    if anchor_idx is None:
        print(f"[error] module_bypass: anchor '{anchor}' not found in {path} — upstream may have refactored version.c!", file=sys.stderr)
        sys.exit(1)

    for i in range(anchor_idx + 1, len(lines)):
        stripped = lines[i].strip()
        if stripped == "return 1;":
            print("[info] module_bypass: already patched — skipping")
            sys.exit(0)
        if stripped == "return 0;":
            lines[i] = lines[i].replace("return 0;", "return 1;", 1)
            with open(path, "w") as f:
                f.writelines(lines)
            print(f"[info] module_bypass: patched return value at line {i + 1} ✅")
            sys.exit(0)

    print(f"[error] module_bypass: 'return 0;' not found after '{anchor}' in {path} — upstream may have refactored version.c!", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
