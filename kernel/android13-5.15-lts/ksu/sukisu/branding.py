import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    old1 = ('KSU_VERSION_FULL := $(if $(call git_short_sha),v$(VERSION_TAG)-$(call git_short_sha)'
            '@$(call git_branch),v$(VERSION_TAG)-$(REPO_NAME)-unknown@unknown)')
    new1 = (old1 + '\n'
            'KSU_VERSION_FULL := $(KSU_VERSION_FULL) Luminaire')

    old2 = 'ccflags-y += -DKSU_VERSION_FULL=\\\"$(KSU_VERSION_FULL)\\\"'
    new2 = "ccflags-y += -DKSU_VERSION_FULL='\"$(KSU_VERSION_FULL)\"'"

    if "KSU_VERSION_FULL := $(KSU_VERSION_FULL) Luminaire" in content:
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
