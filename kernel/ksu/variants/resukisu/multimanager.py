import sys


def main():
    sign_path = sys.argv[1]
    apk_path = sys.argv[2]

    with open(sign_path) as f:
        content = f.read()

    old_sign = ('// KOWX712/KernelSU\n'
                '#define EXPECTED_SIZE_KOWX712 0x375\n'
                '#define EXPECTED_HASH_KOWX712 "484fcba6e6c43b1fb09700633bf2fb4758f13cb0b2f4457b80d075084b26c588"')

    new_sign = ('// KOWX712/KernelSU\n'
                '#define EXPECTED_SIZE_KOWX712 0x375\n'
                '#define EXPECTED_HASH_KOWX712 "484fcba6e6c43b1fb09700633bf2fb4758f13cb0b2f4457b80d075084b26c588"\n'
                '\n'
                '// rifsxd/KernelSU-Next\n'
                '#define EXPECTED_SIZE_KSUNEXT 0x3e6\n'
                '#define EXPECTED_HASH_KSUNEXT "79e590113c4c4c0c222978e413a5faa801666957b1212a328e46c00c69821bf7"\n'
                '\n'
                '// rapli/MamboSU\n'
                '#define EXPECTED_SIZE_MAMBOSU 0x384\n'
                '#define EXPECTED_HASH_MAMBOSU "a9462b8b98ea1ca7901b0cbdcebfaa35f0aa95e51b01d66e6b6d2c81b97746d8"\n'
                '\n'
                '// vortexsu/VortexSU\n'
                '#define EXPECTED_SIZE_VORTEXSU 0x381\n'
                '#define EXPECTED_HASH_VORTEXSU "67eec44718428adad14e6a9dca57822759aba7e77a8cad7071f6f6704df8bb48"\n'
                '\n'
                '// twj/WildKSU\n'
                '#define EXPECTED_SIZE_WILDKSU 0x381\n'
                '#define EXPECTED_HASH_WILDKSU "52d52d8c8bfbe53dc2b6ff1c613184e2c03013e090fe8905d8e3d5dc2658c2e4"')

    if "EXPECTED_SIZE_KSUNEXT" in content:
        print("manager_sign.h already patched, skipping.")
    else:
        if old_sign not in content:
            print("ERROR: target block not found in manager_sign.h!", file=sys.stderr)
            sys.exit(1)
        content = content.replace(old_sign, new_sign)
        with open(sign_path, 'w') as f:
            f.write(content)
        print("manager_sign.h patched.")

    with open(apk_path) as f:
        content = f.read()

    old_apk = ('    { EXPECTED_SIZE_KOWX712, EXPECTED_HASH_KOWX712 }, // KOWX712/KernelSU\n'
               '#ifdef EXPECTED_SIZE')

    new_apk = ('    { EXPECTED_SIZE_KOWX712, EXPECTED_HASH_KOWX712 }, // KOWX712/KernelSU\n'
               '    { EXPECTED_SIZE_KSUNEXT, EXPECTED_HASH_KSUNEXT }, // rifsxd/KernelSU-Next\n'
               '    { EXPECTED_SIZE_MAMBOSU, EXPECTED_HASH_MAMBOSU }, // rapli/MamboSU\n'
               '    { EXPECTED_SIZE_VORTEXSU, EXPECTED_HASH_VORTEXSU }, // vortexsu/VortexSU\n'
               '    { EXPECTED_SIZE_WILDKSU, EXPECTED_HASH_WILDKSU }, // twj/WildKSU\n'
               '#ifdef EXPECTED_SIZE')

    if "EXPECTED_SIZE_KSUNEXT" in content:
        print("apk_sign.c already patched, skipping.")
    else:
        if old_apk not in content:
            print("ERROR: target block not found in apk_sign.c!", file=sys.stderr)
            sys.exit(1)
        content = content.replace(old_apk, new_apk)
        with open(apk_path, 'w') as f:
            f.write(content)
        print("apk_sign.c patched.")


if __name__ == "__main__":
    main()
