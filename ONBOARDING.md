# Onboarding a new GKI kernel version

Checklist for adding support for a new `<android_ver>-<kernel_ver>-lts`
combination (e.g. android13-5.15, android15-6.6, android16-6.12). Written
so the process doesn't live only in one person's head — follow every
step in order; each one exists because skipping it produces a silent gap,
not a loud failure, somewhere else in the pipeline.

---

## 1. `functions.sh` — teach the mapping

Add the new kernel version's Android release to `resolve_android_version()`:

```bash
resolve_android_version() {
    case "${KERNEL_VERSION}" in
        "5.10") echo "android12" ;;
        "5.15") echo "android13" ;;
        "6.1")  echo "android14" ;;
        "6.6")  echo "android15" ;;   # <- new arm goes here
        "6.12") echo "android16" ;;
        *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
    esac
}
```

This function is the single source of truth for the Android-version prefix
used everywhere else below (`KERNEL_BRANCH`, `VERSION_PATCH_DIR`,
`kernel_source_repo()` in caption.py, `scout.sh`'s manifest path, etc.) —
get this arm right first, everything downstream depends on it.

## 2. New per-version folder

```
kernel/<android_ver>-<kernel_ver>-lts/
├── ksu/
│   └── susfs/susfs.sh     # only if this version's SuSFS pairing is verified
└── patches/
    ├── required/     # correctness-only fixes (e.g. KaBI), if any apply
    └── luminaire/     # ADIOS/BORE patch files, once backported
```

`manifest.json` does **not** need to be created up front — `scout.sh`
already handles a missing manifest gracefully (treats it as "no pins/
candidates yet" and warns, doesn't error). It gets created the first time
`checkpoint/engine.sh` promotes a good ref for this version.

Root solutions themselves (`resukisu`, `sukisu`, `ksunext`) are **not**
copied per version anymore — `kernel/ksu-shared/{resukisu,sukisu,ksunext}/`
holds one copy each, since none of them have real per-kernel-version logic
(each fork's own upstream `setup.sh` handles GKI-version detection itself).
Onboarding a new kernel version normally means **zero new files** for
these three — see step 2b instead of creating a `ksu/<variant>/` folder.

`ksu/susfs/susfs.sh` is the one genuine exception — SuSFS pairing really
is per-version (different upstream branch per GKI version, different
KSUNEXT-availability status per fork) — only create this file once you've
actually verified the pairing for this specific kernel version. An
empty/missing `ksu/susfs/susfs.sh` is exactly what `run_variant()` uses to
fail loud if SuSFS is requested for a version it isn't wired up for yet.
Don't pre-create it "for later"; that defeats the gate.

## 2b. `KSU_VARIANT_SUPPORTED_VERSIONS` (`kernel/ksu-shared/registry.sh`)

For every root solution actually verified to build and boot on this new
kernel version, add the version to its space-separated list:

```bash
declare -A KSU_VARIANT_SUPPORTED_VERSIONS=(
    [resukisu]="5.10 5.15 6.1 6.6"   # <- e.g. add 6.6 here once verified
    [sukisu]="5.10 5.15 6.1"
    [ksunext]="5.15 6.1"
)
```

This is the *only* compatibility signal `run_variant()` checks now (it
replaced "does `kernel/<ver>-lts/ksu/<variant>/` exist as a folder" — see
step 2). Don't add a version speculatively; an entry here without the
fork's `setup.sh` actually working on this GKI version will surface as a
build failure inside `kernel/ksu-shared/<variant>/<variant>.sh`, not a
clean skip.

## 3. `ADDON_SUPPORTED_VERSIONS` (`kernel/addons/registry.sh`)

For every addon in `kernel/addons/` that has a working patch/Kconfig path
for this new version, add the version to its space-separated list:

```bash
declare -A ADDON_SUPPORTED_VERSIONS=(
    [rekernel]="6.1"
    [bbrv3]="5.10 6.1 6.6"   # <- e.g. add 6.6 here once verified
    ...
)
```

Don't add a version here speculatively — this map is what gates whether
the addon is even attempted (`addon_supports_kernel_version()`); an addon
listed here without the matching patch/logic actually working will surface
as a build failure inside that addon's own script, not a clean skip.

## 4. `LUMINAIRE_SUPPORTED_VERSIONS` (`kernel/luminaire/registry.sh`)

Same idea, separate map, for the always-on `kernel/luminaire/` features
(currently ADIOS, BORE — no toggle, not part of `$ADDONS`):

```bash
declare -A LUMINAIRE_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [adios]="6.1"
)
```

Only add an entry once the corresponding patch file exists under
`kernel/<ver>-lts/patches/luminaire/` for this version — same
skip-with-warn semantics as addons if you don't.

## 5. Addons with their own per-version logic

Two different patterns exist; check which one each addon uses before
assuming a version bump is free:

**Pattern A — case-switch to an upstream URL, keyed by `${KERNEL_VERSION}`.**
Currently: `ntsync`, `bbrv3`, `zeromount`. Each has a `case "${KERNEL_VERSION}"`
block in its own `.sh` — add a new arm there pointing at the right upstream
patch/branch for this version, in addition to the `ADDON_SUPPORTED_VERSIONS`
entry in step 3 (both are required; the map alone doesn't add the arm).

**Pattern A-variant — version interpolated directly into a filename.**
Currently: `nomount` (looks for
`nomount_${KERNEL_VERSION}_kernel_integration.patch`). No code change
needed in the addon script itself — just make sure the correctly-named
patch file exists under its own patches directory for this version.

**Pattern B — self-maintained patch file per kernel-version folder.**
Currently: `droidspaces` (`patches/required/`), and the two `kernel/luminaire/`
features, `adios`/`bore` (`patches/luminaire/`). No code change needed in
the owning script — it already reads `${VERSION_PATCH_DIR}/patches/...`
generically; just add the version's patch file in the right place (step 2)
and the support-map entry (step 3 or 4).

**Version-agnostic (no per-version logic at all).**
Currently: `wireguard` (config-only, no patch needed on any GKI ≥5.6),
`rekernel`, `bbg`, `kasumi`, `lz4zstd`, `lz4kd`. Nothing to do here beyond
step 3, once verified working on the new version.

If you add a genuinely new addon later, note here which pattern it follows
so this list stays accurate.

## 6. `luminaire.fragment` (`kernel/config/luminaire.fragment`)

This gets merged into **every** kernel version's defconfig unconditionally
— re-validate every `CONFIG_*` symbol in it actually exists in this new
version's Kconfig before assuming it's a no-op include. Symbol names and
availability drift between GKI versions (this bit the ADIOS/BORE Kconfig
symbols before the `kernel/luminaire/` restructure — see git history).
`make listnewconfig`/`olddefconfig`'s output during a Build/Warm Run is
the fastest way to spot an unrecognized symbol here.

## 7. `scout.sh` — confirm no new hardcoded assumptions

Read through `kernel/checkpoint/scout.sh`'s `case "$KERNEL_VARIANT"` block
for whichever root solutions you're wiring up on this version. RESUKISU
and SUKISU's SuSFS pin lookup already derive the branch name dynamically
(`gki-$(resolve_android_version)-${KERNEL_VERSION}`) — those need no
change. KSUNEXT+SUSFS currently has a hard `error()` guard limiting it to
kernel 6.1 only, because pershoot's `susfs4ksu` fork genuinely has no
branch for any other kernel version yet — if that changes upstream (check
https://gitlab.com/pershoot/susfs4ksu's branch list), update that guard,
don't just delete it.

If you're wiring up a root solution/fork combination not covered by any
existing `case` arm at all, that's a new arm to add here, following the
same "derive dynamically where the upstream repo supports it, guard loud
where it doesn't" approach — never a fresh hardcoded value.

## 8. Sanity pass before calling it done

- [ ] `resolve_android_version()` arm added
- [ ] `KSU_VARIANT_SUPPORTED_VERSIONS` updated for every root solution actually verified on this version
- [ ] `kernel/<ver>-lts/ksu/susfs/susfs.sh` exists only if this version's SuSFS pairing is verified (resukisu/sukisu/ksunext themselves need no new per-version files)
- [ ] `ADDON_SUPPORTED_VERSIONS` updated for every addon actually verified on this version
- [ ] `LUMINAIRE_SUPPORTED_VERSIONS` updated if ADIOS/BORE have a backport for this version
- [ ] Pattern A/A-variant addons (ntsync, bbrv3, zeromount, nomount) have their version-specific arm/file in place
- [ ] `luminaire.fragment` re-checked against this version's Kconfig (no unknown-symbol noise in `olddefconfig`)
- [ ] `scout.sh` re-read for this version's root-solution/fork combos — no silently-wrong hardcoded pin
- [ ] A Dry Run and a Warm Run both complete cleanly before attempting a full Build
