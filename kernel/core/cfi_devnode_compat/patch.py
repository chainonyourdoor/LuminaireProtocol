import sys

MARKER = "CFLAGS_REMOVE_core.o"

ANCHOR = "CFLAGS_trace.o\t\t:= -I$(src)"

REPLACEMENT = (
    ANCHOR + "\n\n"
    "CFLAGS_REMOVE_core.o\t+= $(CC_FLAGS_CFI)"
)


def main():
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()

    if MARKER in content:
        print("[info] cfi_devnode_compat: already patched — skipping", flush=True)
        sys.exit(0)

    if ANCHOR not in content:
        print(
            "[error] cfi_devnode_compat: CFLAGS_trace.o anchor not found in "
            "drivers/base/Makefile — upstream may have changed it, refusing to guess",
            flush=True,
        )
        sys.exit(1)

    content = content.replace(ANCHOR, REPLACEMENT, 1)

    with open(path, "w") as f:
        f.write(content)

    print("[info] cfi_devnode_compat: CFI disabled for core.o at the Makefile level ✅", flush=True)


if __name__ == "__main__":
    main()
