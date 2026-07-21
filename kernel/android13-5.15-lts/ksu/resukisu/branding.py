import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    old1 = 'KSU_VERSION_FULL := $(subst %KSU_VERSION%,$(KSU_VERSION),$(KSU_VERSION_FULL))'
    new1 = ('KSU_VERSION_FULL := $(subst %KSU_VERSION%,$(KSU_VERSION),$(KSU_VERSION_FULL))\n'
            'KSU_VERSION_FULL := $(KSU_TAG_NAME) Luminaire')

    old2 = 'ccflags-y += -DKSU_VERSION_FULL=\\\"$(KSU_VERSION_FULL)\\\"'
    new2 = "ccflags-y += -DKSU_VERSION_FULL='\"$(KSU_VERSION_FULL)\"'"

    if "KSU_VERSION_FULL := $(KSU_TAG_NAME) Luminaire" in content:
        print("Branding already applied, skipping.")
        sys.exit(0)

    if old1 not in content:
        print("ERROR: VERSION_FULL line not found!", file=sys.stderr)
        sys.exit(1)

    if old2 not in content:
        print("ERROR: ccflags VERSION_FULL line not found!", file=sys.stderr)
        sys.exit(1)

    content = content.replace(old1, new1).replace(old2, new2)

    with open(path, 'w') as f:
        f.write(content)

    print("Branding injected successfully.")


if __name__ == "__main__":
    main()
