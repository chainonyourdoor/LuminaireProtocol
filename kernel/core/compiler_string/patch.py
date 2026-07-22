import sys, re


def main():
    path = sys.argv[1]
    compiler_string = sys.argv[2] if len(sys.argv) > 2 else ""
    with open(path, "r") as f:
        content = f.read()
    clean_ld = (
        "LD_VERSION=$(LC_ALL=C $LD -v 2>/dev/null | head -n1 | "
        "grep -oP 'LLD\\s+\\K[0-9]+\\.[0-9]+\\.[0-9]+' | "
        "head -n1 | sed 's/^/LLD /')"
    )
    if f'CC_VERSION="{compiler_string}"' in content and clean_ld in content:
        print("[info] compiler_string_patch: already patched — skipping", flush=True)
        sys.exit(0)
    lines = content.split("\n")
    out = []
    i = 0
    cc_replaced = False
    ld_replaced = False
    while i < len(lines):
        line = lines[i]
        if not cc_replaced and re.match(r'\s*CC_VERSION="\$\d+"', line):
            out.append(f'CC_VERSION="{compiler_string}"')
            i += 1
            cc_replaced = True
            continue
        if not ld_replaced and re.match(r"\s*LD_VERSION=\$\(", line):
            depth = 0
            in_squote = False
            j = i
            while j < len(lines):
                for ch in lines[j]:
                    if ch == "'":
                        in_squote = not in_squote
                    elif not in_squote:
                        if ch == "(":
                            depth += 1
                        elif ch == ")":
                            depth -= 1
                if depth <= 0:
                    break
                j += 1
            out.append(clean_ld)
            i = j + 1
            ld_replaced = True
            continue
        out.append(line)
        i += 1
    if not cc_replaced:
        print("[warn] compiler_string_patch: CC_VERSION pattern not matched in mkcompile_h", flush=True)
    if not ld_replaced:
        print("[warn] compiler_string_patch: LD_VERSION pattern not matched in mkcompile_h", flush=True)
    if not cc_replaced and not ld_replaced:
        print("[warn] compiler_string_patch: no patterns matched — skipping write", flush=True)
        sys.exit(0)
    if not cc_replaced or not ld_replaced:
        print("[error] compiler_string_patch: partial match — aborting to prevent inconsistent compiler string", flush=True)
        sys.exit(1)
    with open(path, "w") as f:
        f.write("\n".join(out))
    print(f"[info] mkcompile_h patched: CC='{compiler_string}', LD='LLD X.Y.Z' ✅", flush=True)


if __name__ == "__main__":
    main()
