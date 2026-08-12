import sys

MARKER = "luminaire: force MGLRU on"

CAPS_ANCHOR = (
    "\telse if (kstrtouint(buf, 0, &caps))\n"
    "\t\treturn -EINVAL;\n"
    "\n"
    "\tfor (i = 0; i < NR_LRU_GEN_CAPS; i++) {"
)

CAPS_REPLACEMENT = (
    "\telse if (kstrtouint(buf, 0, &caps))\n"
    "\t\treturn -EINVAL;\n"
    "\n"
    "\t/* " + MARKER + ": ignore what was written, always request every\n"
    "\t * cap the running kernel/hardware supports. Unsupported caps are\n"
    "\t * still dropped below by the normal capability checks.\n"
    "\t */\n"
    "\tcaps |= BIT(LRU_GEN_CORE) | BIT(LRU_GEN_MM_WALK) | BIT(LRU_GEN_NONLEAF_YOUNG);\n"
    "\n"
    "\tfor (i = 0; i < NR_LRU_GEN_CAPS; i++) {"
)

STATE_ANCHOR = (
    "\t\tif (i == LRU_GEN_CORE)\n"
    "\t\t\tlru_gen_change_state(enabled);"
)

STATE_REPLACEMENT = (
    "\t\tif (i == LRU_GEN_CORE)\n"
    "\t\t\tlru_gen_change_state(true);"
)


def main():
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()

    if MARKER in content:
        print("[info] mglru_force_enable: already patched — skipping", flush=True)
        sys.exit(0)

    if CAPS_ANCHOR not in content:
        print(
            "[error] mglru_force_enable: caps anchor not found in expected form "
            "— upstream may have refactored store_enabled(), refusing to guess",
            flush=True,
        )
        sys.exit(1)

    if STATE_ANCHOR not in content:
        print(
            "[error] mglru_force_enable: lru_gen_change_state anchor not found "
            "in expected form — upstream may have refactored store_enabled(), "
            "refusing to guess",
            flush=True,
        )
        sys.exit(1)

    content = content.replace(CAPS_ANCHOR, CAPS_REPLACEMENT, 1)
    content = content.replace(STATE_ANCHOR, STATE_REPLACEMENT, 1)

    with open(path, "w") as f:
        f.write(content)

    print("[info] mglru_force_enable: all caps forced, CORE state hardcoded ✅", flush=True)


if __name__ == "__main__":
    main()
