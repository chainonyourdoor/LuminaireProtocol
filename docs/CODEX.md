# LuminaireProtocol — CODEX

All technical reasoning, bug-fix history, and non-obvious context that used
to be scattered as comments across 72+ scripts is collected here. The
scripts themselves now contain only logic + shebang + (for
addon/root-solution/luminaire features) the repo header banner — so the
flow reads cleanly without explanatory paragraphs in the way. If a line of
code looks odd or unclear, look here first before trying to "simplify" it.

Organized per-path, matching the repo's folder structure.

## Table of Contents

- [build.sh](#buildsh)
- [functions.sh](#functionssh)
- [kernel/checkpoint/scout.sh](#kernelcheckpointscoutsh)
- [kernel/checkpoint/engine.sh](#kernelcheckpointenginesh)

---

## `build.sh`

**`exec 2>&1`** (first line) — GitHub Actions captures stdout and stderr as
2 separate buffered streams and doesn't guarantee their relative order when
rendered in the log. `log()`/`warn()`/`error()` write to stderr while
`::group::`/`::endgroup::` write to stdout — without this, log lines can
render outside the `::group::` block they were actually written in.
Merging stderr into stdout here makes everything one stream, preserving
the real write order.

**`DRY_RUN`** — skips the actual compile (see `build/make.sh`) so the rest
of the pipeline can be tested quickly after a refactor. Derived in
`build.yml` from `RUN_MODE=="Dry Run"`, so it can never go out of sync with
`RUN_MODE` by the time it reaches here.

**Registry sourcing at the top (`kernel/{addons,luminaire,ksu-shared}/registry.sh`)**
— defines `run_addons()`/`run_luminaire()` (plus their respective
version-support maps) here, not inside `main()`, so it's just a regular
function call in `main()` like everything else, and `build.sh` doesn't
need to know any addon/luminaire policy at all.

**`wait_for_apt` in `main()`** — waits for the background `apt install`
(started in `01_deps.sh`) to finish — `02_ccache.sh` (cmake/ninja/g++) and
`build/make.sh` (bc/bison/flex) need these packages already present before
running. `arsenal.sh` has always done this from the start; `build.sh`
previously didn't, which could race on fresh runners.

**`run_variant()`** — an unsupported root solution is NOT an optional skip
(unlike addons) — the release label (`Ak3-*-${KERNEL_VARIANT}-*.zip`) is
identity-critical, so shipping a vanilla build labeled KSUNEXT/etc. just
because the variant isn't supported for this kernel version is worse than
the build failing outright and explicitly.

**`run_core()`** — an explicit list of scripts (not a glob of every `.sh`
in the folder) so no accidental sourcing of temp/irrelevant files.

**Why `run_luminaire()`/`run_addons()` aren't defined in `build.sh`** —
both (plus the version-support map & addon conflict matrix) live in
`kernel/luminaire/registry.sh` and `kernel/addons/registry.sh`, sourced
near the top of this file. Deliberately kept out of `build.sh` so this
file stays the orchestrator (deciding WHEN something runs) rather than
also owning WHAT is supported.

**`run_postbuild()`** — deliberately separate from `run_addons()`/
`run_build()`: addons in `run_addons()` patch source/defconfig and get
compiled together into one vmlinux build in `run_build()`. Some addons need
work AFTER `run_build()` finishes — e.g. Kasumi's out-of-tree LKM needs
`Module.symvers` from the freshly-built kernel tree, which doesn't exist
before that point.

This is a thin dispatcher, shaped the same way as `run_build()`: it
doesn't know/care what a given addon's postbuild step does (compiling an
LKM, or whatever any future addon needs) — it just runs
`kernel/addons/<name>/postbuild.sh` for every addon that was actually
*applied*. The gate is membership in `$APPLIED_ADDONS` (the version-filtered
result list from `run_addons()`), NOT the raw `$ADDONS` — an addon skipped
there (kernel version unsupported) never had its main script run, so state
it would normally export (e.g. Kasumi's `$KASUMI_SRC_DIR`) never exists
either. If the gate used raw `$ADDONS`, it would still try to run its
`postbuild.sh` and fail due to that missing state. Addons without a
`postbuild.sh` (the majority — patch/Kconfig-only ones) are automatically
skipped here, no separate "enabled" flag needed.


## `functions.sh`

**`run_quiet()`** — capturing the exit code `$?` is done on its own line
right after the command runs, not via `if cmd; then ...; fi` with no
`else`. Reason: bash resets `$?` to 0 for that construct when the
condition is false — silently turning every command failure into a "false
success". The same pattern is reused in `retry()`.

**`mark_stage_ok()`** — called right after each `build.sh` stage finishes
(see `main()`). Thanks to `set -e`, a failing stage exits before it gets a
chance to call its own `mark_stage_ok` — so `kernel/checkpoint/engine.sh`
can tell which stage failed just by checking which markers made it into
that job's env. This is what keeps `engine.sh` from wrongly blaming a
KSU-fork/SuSFS candidate for a failure that actually happened in a
different stage (e.g. `run_addons`, or `run_postbuild` — an addon like
Kasumi failing its post-build LKM compile) rather than in
`run_variant`/`run_build` (where that candidate is actually used). No-op
outside CI (`GITHUB_ENV` unset), so it's safe to call from a manual/local
`build.sh` run too.

**`write_dry_run_image()`** — used by `build/make.sh` when `DRY_RUN=true`
(only set by `build.yml` when `RUN_MODE="Dry Run"`). Writes a placeholder
file at the path where the real kernel Image would go, so the packaging
step `release/anykernel.sh` (and everything downstream of it — Telegram
notification, checkpoint promotion) can be tested without actually
compiling.

**`resolve_android_version()`** — maps `KERNEL_VERSION` (e.g. "6.1") to its
`ANDROID_VERSION` branch prefix (e.g. "android14"). Used by both
`build.sh` and `arsenal.sh`, so the version table only needs updating in
one place when adding a new kernel version.

**`run_setup()`** — sources every `*.sh` in `setup/`, in order. Used by
both `build.sh` and `arsenal.sh`.

**`run_step()`** — the generic form of the "check file exists ->
`::group::` -> source -> `::endgroup::`" pattern repeated throughout
`build.sh`'s single-file dispatch steps (`restore_kernel_source`, 2 calls
in `run_variant`, `run_build`, `run_release`). Args: `<emoji> <label for
::group:: and error> <script path> <error message if script is missing>`.

**`wait_for_apt()`** — waits for the background `apt install` triggered by
`setup/01_deps.sh` (`APT_PID`). Used by both `build.sh` and `arsenal.sh` so
a fresh runner doesn't proceed to the ccache/build step before the needed
packages are installed. Polling is capped at 10 minutes (not a bare `wait`
with no timeout) — Setup Arsenal run #430 once got stuck 17+ minutes with
no signal at all. 10 minutes is more than enough to install this package
list from a cold cache even repeatedly; past that, something is actually
wrong.

**`retry()`** — retries a command with exponential backoff. Usage:
`retry <max_attempts> <command...>`. Captures `$?` using the same pattern
as `run_quiet()` (its own line, not via `if cmd; then...; fi` with no
`else`).

**`cache_freshness_note()`** — logs a note for restoring the clang/kernel-
source/AK3 cache, explaining WHY that cache was restored (not just "restore
succeeded"). `Start-Build` always restores (`USE_*_CACHE` hardcoded "true"
there) — `Prepare Arsenal` is the only point that decides whether this
shared cache is actually fresh for this run (`CACHE_REFRESHED`, from the
'Update Arsenal' input). Without this, "restored from cache ✅" reads the
same whether the cache is brand new or weeks old — misleading when reading
a single job's log in isolation.

**`mode_emoji()`** — emoji lookup per `RUN_MODE`, used in `build.sh`'s
open/close banner. Deliberately split out as a lookup (rather than
attaching an emoji directly to `RUN_MODE`), because `RUN_MODE` is compared
with exact-string matches elsewhere (`scout.sh`, `telegram.sh`, and
`build.sh` itself via `"${RUN_MODE^^}" = "WARM RUN"`) — mutating the value
here would silently break those comparisons.

---

## `kernel/checkpoint/scout.sh`

**Purpose of this file**: determine the git ref (commit SHA) that each
tracked upstream component (ReSukiSU, SukiSU-Ultra, SuSFS) should use for
this build.

- `RUN_MODE=Release`: always use the known-good pin from the manifest.
  Never queries upstream, never builds an untested candidate.
- `RUN_MODE=Build/Warm Run`: queries the latest upstream commit. If it
  differs from the pin and isn't known-bad, it becomes a candidate for
  this run — `kernel/checkpoint/engine.sh` decides after the build whether
  to promote or blacklist it.
- **Exception (deadlock-breaking retest)**: if there's no known-good pin
  at all AND the latest upstream commit is already blacklisted, there's no
  known-good ref to fall back to. Falling back to an empty ref would make
  the build script silently default to cloning the upstream branch HEAD
  (the same SHA that was just blacklisted) without ever recording it as a
  candidate — a permanent deadlock where Release mode can never pass no
  matter how many Warm Run/Build successes happen. In this specific case
  only, the blacklisted ref is retried as a last-resort candidate so the
  actual build outcome can either promote it or re-blacklist it.

Exported (via `$GITHUB_ENV`) for each relevant component:
`<COMPONENT>_REF` (the SHA actually used for the build),
`CANDIDATE_<COMPONENT>` ("true" if that REF is an unverified candidate).

**Manifest not yet existing** (`kernel/<ver>/manifest.json` not found) —
just means no pin has ever been promoted for this version yet, normal for
a kernel version with no checkpoint history, not a misconfiguration. Falls
back to an empty object `{}` so `resolve_component`'s `// ""` / `// []`
defaults still work the same as when the fork's key just isn't in an
existing manifest.

**`latest_sha_or_empty()`** — never fails the build; a lookup problem just
means "no candidate this run, use the pin". `GH_API_AUTH` is a GitHub
PAT — only attached for calls to `api.github.com`. Sending it to a
non-GitHub target like `gitlab.com` (e.g. the SuSFS lookup) makes the
Authorization header look foreign/invalid from GitLab's point of view,
which gets rejected quickly (~300ms, consistent every run — not a
timeout/rate-limit profile). Scoping the header to its actual target
avoids this; logging `http_code`/`curl_exit` below it gives concrete
evidence if a lookup fails again later.

**`resolve_component()`** — resolves one component: compares latest
upstream vs. pin + bad-list, exports `<COMPONENT>_REF` /
`CANDIDATE_<COMPONENT>` to `$GITHUB_ENV`. Deadlock case (`is_bad=true` and
`good` empty): without this branch, `ref` would fall back to an empty
`$good` forever — downstream build scripts would silently default to
cloning the upstream branch HEAD (exactly this "bad" SHA), but since
`candidate` still reads "false" here, `engine.sh` never gets a chance to
promote it even if the build succeeds. Effect: Release mode would never
pass for this component, no matter how many Warm Run/Build runs go green
(confirmed happening in practice for SUKISU+SUSFS: `sukisu_builtin` stuck
at `b88403d2561b` since being blacklisted in run 28687541974; the upstream
builtin branch hasn't moved since). Fix: retry it as a last-resort
candidate — success means promote & the deadlock breaks; failure just
re-blacklists the same SHA (`engine.sh`'s `bad |= (. + [...]) | unique`
makes that a no-op), so it can't get worse than the permanent-failure
state it replaces.

**`RESUKISU` case**: SuSFS pairing uses `simonpunk/susfs4ksu` branch
`gki-<android_ver>-<kernel_ver>` directly.

**`SUKISU` case, SuSFS enabled**: the `"builtin"` branch is
SukiSU-Ultra's own SuSFS-integrated line — actively maintained by the
SukiSU-Ultra team to stay in sync with SuSFS, unlike `"main"` which has
moved to an architecture (`syscall_hook_manager`) that isn't compatible
with SuSFS's adapter patch at all. So for the SUSFS case, this branch's
tip is tracked directly, same model as tracking ReSukiSU. Non-SUSFS
SukiSU-Ultra: its own upstream `setup.sh` defaults to the latest *tag*
(not HEAD of `main`) when no ref is given — matched here to keep the same
semantics.

**`KSUNEXT` case, SuSFS enabled**: the SuSFS source for this pairing comes
from the official `simonpunk/susfs4ksu` (same as ReSukiSU/SukiSU-Ultra
above), NOT from pershoot's susfs4ksu fork. Verified directly against
source: pershoot's KernelSU-Next dev-susfs fork only calls `susfs_*`
symbols already provided by the official `susfs4ksu`
(`susfs_is_current_proc_umounted`/`susfs_set_current_proc_umounted` as
`static inline` in `susfs_def.h`, the `st_susfs_uname`/
`st_susfs_avc_log_spoofing` structs in `susfs.h`, etc.) — pershoot's own
SELinux/hook additions (`kernel/selinux/`, `kernel/hook/`) are
self-contained and need nothing extra from susfs4ksu. `susfs_def.h` is
byte-identical across simonpunk's `gki-android14-6.1-dev`,
`gki-android13-5.15-dev`, and `gki-android12-5.10-dev` branches, so this
pairing works identically for every kernel version — no per-version
restriction needed here. Non-SUSFS KernelSU-Next: its own upstream
`setup.sh` defaults to the latest *tag* when no ref is given (same
semantics as non-SUSFS SukiSU-Ultra) — matched here too.

---

## `kernel/checkpoint/engine.sh`

**Purpose of this file**: runs after the build step (always, even on
failure).

- Candidate succeeded → promote: manifest's `"good"` becomes this SHA.
- Candidate failed → blacklist: append to `"bad"`, `"good"` untouched
  (that IS the rollback — nothing else changes).
- No candidate used this run → do nothing.

Matrix jobs (RESUKISU/SUKISU) run in parallel and may write
`manifest.json` at the same time, so every write goes through a
fetch-rebase-push retry loop, not a single commit+push.

Args: `<build outcome: "success" | "failure"> <space-separated component
keys to check, e.g. "resukisu susfs">`

**Why `REMOTE` is constructed manually with `PERSONAL_TOKEN`** — the
`github-actions[bot]` push 403 issue was already fixed at the checkout
step in `build.yml`'s `Start-Build` (`persist-credentials: false`), NOT
here. `actions/checkout` v6+ persists the auth header it injects via a
global `includeIf.gitdir` config pointing to a file under `$RUNNER_TEMP`,
not this repo's local `.git/config` — so unsetting
`http.https://github.com/.extraheader` here has no effect; the fix has to
be at that checkout step itself (see the `actions/checkout` v6
changelog/issue tracker, PR "Persist creds to a separate file").

**`apply_and_push()`** — applies one jq patch to `manifest.json` on top of
the latest `main`, pushes, retries on fast-forward conflict from another
concurrently-running matrix job.

- `git reset -q --hard FETCH_HEAD` after fetch: MUST actually move the
  local HEAD to `FETCH_HEAD` before committing — `git fetch` alone doesn't
  do that. Without this line, every retry re-commits on top of the same
  stale parent, so a real conflict (from another concurrent matrix job's
  push) fails identically every attempt and this loop would never
  actually recover (confirmed via a real 2-clone repro before this fix
  landed: 0/5 attempts succeeded without this line, 1/1 with it).
  `workspace/` is gitignored, so this never touches the in-progress kernel
  source tree.
- First-ever checkpoint write for this kernel version: the file (and its
  folder) doesn't exist yet in the repo. That's normal, not an error —
  bootstraps an empty object so jq has something to patch.
- A failing jq here used to be silently swallowed: `mv` never ran,
  `manifest.json` never changed, git found "nothing to commit", and
  `apply_and_push` returned 0 as if the update had actually happened —
  confirmed this actually occurred on the promote path (`.bad -= [...]`
  erroring when `.bad` is null/missing, which hits every `manifest.json`
  right after a fresh reset). Now fails loud so a broken `jq_patch` is
  never mistaken for a legitimate no-op.

**`file_issue()`** — opens (or leaves open) a GitHub Issue for a broken
upstream component, deduped by a stable title so repeated retest failures
don't spam it. `gh issue create` fails entirely (no issue created at all)
if the label doesn't already exist in the repo — so it's created
idempotently first.

**Main loop, per component, failure case** — `build.sh`'s `main()` only
sets these markers via `mark_stage_ok()` (see `functions.sh`) after the
relevant stage actually finishes — `set -e` means a failing stage never
reaches its own marker, so the marker's presence tells `engine.sh` which
stage failed without it needing to know any of `build.sh`'s internal
state.

- `CHECKPOINT_VARIANT_OK` missing → failed at/before `run_variant`,
  exactly where this candidate ref is applied → blame it.
- `CHECKPOINT_VARIANT_OK` present but `CHECKPOINT_ADDONS_OK` missing →
  failed in `run_core` or `run_addons`, neither related to the
  KSU-fork/SuSFS candidate this component tracks → leave the pin alone.
- `CHECKPOINT_ADDONS_OK` present but `CHECKPOINT_BUILD_OK` missing →
  failed in `run_build` itself (the actual compile), which the
  candidate's patch could plausibly cause → blame it, same as the
  `run_variant` failure case.
- `CHECKPOINT_BUILD_OK` present → `run_build` already finished, so the
  failure happened in `run_postbuild` (e.g. Kasumi's out-of-tree LKM
  compile) — unrelated to the KSU-fork/SuSFS candidate, which is only
  used in `run_variant`/`run_build` → leave the pin alone. This used to be
  treated the same as the `run_build` case above (no marker existed
  between the two), which wrongly blacklisted the `susfs_resukisu`/
  `susfs_sukisu` candidate `be08face56c3` for kernel 5.10 due to an
  unrelated Kasumi post-build failure — see `manifest.json` history.
