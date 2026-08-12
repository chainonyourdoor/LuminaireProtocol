import sys

MARKER = "__nocfi *device_get_devnode"

OLD_SIG = (
    "const char *device_get_devnode(struct device *dev,\n"
    "\t\t\t       umode_t *mode, kuid_t *uid, kgid_t *gid,\n"
    "\t\t\t       const char **tmp)"
)

NEW_SIG = (
    "const char __nocfi *device_get_devnode(struct device *dev,\n"
    "\t\t\t       umode_t *mode, kuid_t *uid, kgid_t *gid,\n"
    "\t\t\t       const char **tmp)"
)


def main():
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()

    if MARKER in content:
        print("[info] cfi_devnode_compat: already patched — skipping", flush=True)
        sys.exit(0)

    if OLD_SIG not in content:
        print(
            "[error] cfi_devnode_compat: device_get_devnode signature not found "
            "in expected form — upstream may have changed it, refusing to guess",
            flush=True,
        )
        sys.exit(1)

    content = content.replace(OLD_SIG, NEW_SIG, 1)

    with open(path, "w") as f:
        f.write(content)

    print("[info] cfi_devnode_compat: __nocfi applied to device_get_devnode ✅", flush=True)


if __name__ == "__main__":
    main()
