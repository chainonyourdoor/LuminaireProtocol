import sys


ANCHOR = "#ifdef USE_PKCS11_ENGINE\nstatic const char *key_pass;\n#endif"

DEFINE_BLOCK = (
    "/* Luminaire: USE_PKCS11_ENGINE is used below to gate key_pass but is\n"
    " * never actually defined upstream in this file (partial OpenSSL-3\n"
    " * backport) -- define it here whenever ENGINE API is available. */\n"
    "#if !defined(OPENSSL_NO_ENGINE) && !defined(OPENSSL_NO_DEPRECATED_3_0)\n"
    "#define USE_PKCS11_ENGINE\n"
    "#endif\n"
)


def main():
    path = sys.argv[1]
    with open(path, "r") as f:
        content = f.read()
    if "#define USE_PKCS11_ENGINE" in content:
        print("[info] openssl3_compat_patch: already patched — skipping", flush=True)
        sys.exit(0)
    if ANCHOR not in content:
        print(
            "[error] openssl3_compat_patch: anchor not found in extract-cert.c — "
            "upstream may have changed this file, check manually!",
            flush=True,
        )
        sys.exit(1)
    content = content.replace(ANCHOR, DEFINE_BLOCK + ANCHOR, 1)
    with open(path, "w") as f:
        f.write(content)
    print("[info] extract-cert.c patched: USE_PKCS11_ENGINE now defined ✅", flush=True)


if __name__ == "__main__":
    main()
