import sys, re


def main():
    path = sys.argv[1]
    compiler_string = sys.argv[2] if len(sys.argv) > 2 else ""

    with open(path, "r") as f:
        content = f.read()

    # mkcompile_h is called by the kernel Makefile — the exact positional
    # arg number varies by kernel version/convention:
    #   - GKI 6.1-style (trimmed): scripts/mkcompile_h "$(UTS_MACHINE)"
    #     "$(CONFIG_CC_VERSION_TEXT)" "$(LD)"  →  CC_VERSION="$2"
    #   - Older/mainline-style (e.g. 5.10's GKI tree, still close to
    #     upstream scripts/mkcompile_h): TARGET/ARCH/SMP/PREEMPT/
    #     PREEMPT_RT/CC_VERSION/LD as $1.."$7  →  CC_VERSION="$6"
    # The regex below matches CC_VERSION="$N" for any N so this doesn't
    # need a per-kernel-version special case — confirmed both patterns
    # exist in the wild (android14-6.1-lts: $2, android12-5.10-lts: $6).
    #
    # CONFIG_CC_VERSION_TEXT is baked at defconfig time from raw
    # "clang --version" output — KBUILD_COMPILER_STRING is never used
    # here. We hardcode CC_VERSION to our clean string directly.
    #
    # LD_VERSION reads raw "ld.lld -v" output with full LLVM commit URL.
    # We replace it with a clean extraction that yields "LLD X.Y.Z" only.
    #
    # Result: LINUX_COMPILER = "Cirrus Clang 23.0.0, LLD 23.0.0"

    clean_ld = (
        "LD_VERSION=$(LC_ALL=C $LD -v 2>/dev/null | head -n1 | "
        "grep -oP 'LLD\\s+\\K[0-9]+\\.[0-9]+\\.[0-9]+' | "
        "head -n1 | sed 's/^/LLD /')"
    )

    # Idempotency check (same convention as module_bypass/patch.py). Without
    # this, re-running the patcher against an already-patched file hits a
    # false "partial match": the CC pattern (CC_VERSION="$2") no longer
    # matches since it's now a literal string, but the LD pattern
    # (LD_VERSION=$() still matches its own already-patched replacement
    # (clean_ld also starts with "LD_VERSION=$(") — cc_replaced=False,
    # ld_replaced=True, which trips the fatal partial-match abort below
    # even though the file is actually fully and correctly patched already.
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
            # Track paren depth to find where this multi-line LD_VERSION=$(...)
            # assignment actually closes. Must ignore parens inside single
            # quotes — the sed pattern 's/(compatible with [^)]*)//' has
            # literal '(' ')' chars that aren't real shell grouping. Naive
            # raw counting broke on android12-5.10-lts's mkcompile_h, where
            # that whole quoted sed clause sits on the SAME line as the
            # opening "$(": depth hit 0 after just that one line (the quoted
            # parens happened to balance out), leaving the real closing line
            # (" | sed '...')" ) unconsumed as an orphan — which starts with
            # "|", causing a shell syntax error at runtime. android14-6.1-lts's
            # version has the sed clause on its own separate line, so the same
            # naive counting happened to land on the right line there by
            # coincidence, masking the bug until this kernel version.
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
        # Partial match — writing a half-patched file would produce inconsistent
        # compiler string (e.g. CC patched but LD still raw LLVM URL output).
        # Treat as fatal so the issue is visible rather than silently wrong.
        print("[error] compiler_string_patch: partial match — aborting to prevent inconsistent compiler string", flush=True)
        sys.exit(1)

    with open(path, "w") as f:
        f.write("\n".join(out))

    print(f"[info] mkcompile_h patched: CC='{compiler_string}', LD='LLD X.Y.Z' ✅", flush=True)


if __name__ == "__main__":
    main()
