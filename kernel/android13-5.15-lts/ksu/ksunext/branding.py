import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    # KernelSU-Next's Kbuild has no KSU_VERSION_FULL (unlike ReSukiSU/
    # SukiSU-Ultra) — it only builds KSU_VERSION_TAG from KSU_GIT_TAG (or a
    # hardcoded fallback when not a git repo), so that's the anchor here.
    #
    # Kbuild consumes KSU_VERSION_TAG unquoted in ccflags-y (just \"...\"
    # with no surrounding single quotes), so a space in the branding suffix
    # breaks shell tokenization of ccflags-y and clang chokes on the
    # second half as a bogus input file. Wrap both ccflags-y lines in
    # single quotes to make the whole define one token — same fix already
    # applied in resukisu/branding.py and sukisu/branding.py.
    old1 = '$(eval KSU_VERSION_TAG=$(KSU_GIT_TAG))'
    new1 = '$(eval KSU_VERSION_TAG=$(KSU_GIT_TAG) Luminaire)'

    old2 = 'KSU_VERSION_TAG_FALLBACK := v0.0.1'
    new2 = 'KSU_VERSION_TAG_FALLBACK := v0.0.1 Luminaire'

    old3 = "ccflags-y += -DKSU_VERSION_TAG=\\\"$(KSU_VERSION_TAG)\\\""
    new3 = "ccflags-y += -DKSU_VERSION_TAG='\"$(KSU_VERSION_TAG)\"'"

    old4 = "ccflags-y += -DKSU_VERSION_TAG=\\\"$(KSU_VERSION_TAG_FALLBACK)\\\""
    new4 = "ccflags-y += -DKSU_VERSION_TAG='\"$(KSU_VERSION_TAG_FALLBACK)\"'"

    if 'KSU_GIT_TAG) Luminaire' in content:
        print("Branding already applied, skipping.")
        sys.exit(0)

    checks = [
        (old1, "VERSION_TAG"),
        (old2, "VERSION_TAG fallback"),
        (old3, "ccflags VERSION_TAG"),
        (old4, "ccflags VERSION_TAG fallback"),
    ]
    for old, label in checks:
        if old not in content:
            print(f"ERROR: {label} line not found!", file=sys.stderr)
            sys.exit(1)

    content = (
        content
        .replace(old1, new1)
        .replace(old2, new2)
        .replace(old3, new3)
        .replace(old4, new4)
    )

    with open(path, 'w') as f:
        f.write(content)

    print("Branding injected successfully.")


if __name__ == "__main__":
    main()
