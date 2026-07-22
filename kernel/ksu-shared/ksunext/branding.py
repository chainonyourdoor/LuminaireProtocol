import sys


def main():
    path = sys.argv[1]
    with open(path) as f:
        content = f.read()
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
