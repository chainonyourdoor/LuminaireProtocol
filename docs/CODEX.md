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
- [release/telegram/caption.py](#releasetelegramcaptionpy)
- [release/telegram/channel_post.sh](#releasetelegramchannel_postsh)
- [release/telegram/telegram.sh](#releasetelegramtelegramsh)
- [kernel/config/defconfig.sh](#kernelconfigdefconfigsh)
- [kernel/ksu-shared/fix_namespace.py](#kernelksu-sharedfix_namespacepy)
- [kernel/addons/zeromount/inject_namei.py](#kerneladdonszeromountinject_nameipy)
- [kernel/addons/zeromount/inject_readdir.py](#kerneladdonszeromountinject_readdirpy)
- [kernel/addons/zeromount/strip_namei_hunk.py](#kerneladdonszeromountstrip_namei_hunkpy)
- [kernel/addons/zeromount/strip_readdir_hunk.py](#kerneladdonszeromountstrip_readdir_hunkpy)
- [kernel/addons/zeromount/fix_taskmmu.py](#kerneladdonszeromountfix_taskmmupy)
- [kernel/addons/rekernel/inject.py](#kerneladdonsrekernelinjectpy)
- [kernel/addons/bbrv3/enforcer.py](#kerneladdonsbbrv3enforcerpy)
- [kernel/core/compiler_string/patch.py](#kernelcorecompiler_stringpatchpy)
- [kernel/core/openssl3_compat/patch.py](#kernelcoreopenssl3_compatpatchpy)
- [kernel/ksu-shared/ksunext/branding.py](#kernelksu-sharedksunextbrandingpy)
- [release/telegram/telegraph_page.py](#releasetelegramtelegraph_pagepy)
- [kernel/addons/lz4zstd/lz4zstd.sh](#kerneladdonslz4zstdlz4zstdsh)
- [kernel/{android12-5.10,android13-5.15,android14-6.1}/ksu/susfs/susfs.sh](#kernelandroid12-510android13-515android14-61ksususfssusfssh)
- [kernel/ksu-shared/ksunext/ksunext.sh](#kernelksu-sharedksunextksunextsh)
- [kernel/addons/kasumi/kasumi.sh](#kerneladdonskasumikasumish)
- [kernel/addons/kasumi/postbuild.sh](#kerneladdonskasumipostbuildsh)

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

---

## `release/telegram/caption.py`

**`PUSH_TEXT_LIMIT`** — Telegram's `sendMessage` text limit (4096), kept
separate from `CAPTION_LIMIT` (1024) which is the `sendDocument`/
`sendPhoto` caption limit used everywhere else in this file.

**`ADDON_DISPLAY_NAMES`** — single source of truth for addon display
names, shared by `build_blocks()` (per-build group caption) and
`build_channel_caption()` (channel post). Adding a new addon only means
adding an entry here (plus `TOGGLE_ADDON_ORDER` below if it should show as
an explicit Enable/Disable line in the group caption's Add-ons block).

**`MOUNTLESS_ADDON_TOKENS`** — mountless-engine addons are mutually
exclusive (only one, or none, active per build) and shown as a single
"Mountless Engine" line rather than their own Enable/Disable row.

**`TOGGLE_ADDON_ORDER`** — toggle-style addons shown as explicit
Enable/Disable lines in the group caption, in display order.

**`CORE_PATCH_DISPLAY_NAMES` / `CORE_PATCH_ORDER`** — always-on Luminaire
features (`kernel/luminaire/*`, see `build.sh`'s `run_luminaire()`) —
structurally separate from `ADDON_DISPLAY_NAMES`/`TOGGLE_ADDON_ORDER`
since these have no Enable/Disable toggle at all; a build either has the
feature (kernel version supports it) or shows N/A (not backported yet),
never a user-chosen Disable. Named `CORE_PATCH_*` (not `LUMINAIRE_*`) to
match the "Core-Patch" caption label and avoid confusion with
`block_luminaire` (the unrelated Kernel/Source/Toolchain overview block
further down).

**`FRAGMENT_FEATURES`** — human-readable summary of
`kernel/config/luminaire.fragment`, the always-on feature set baked into
every build regardless of which addons are toggled. Hand-curated (the
fragment itself is raw Kconfig, not something to surface verbatim to
readers) and used only by `build_telegraph_content()`. Keep this in sync
manually whenever `luminaire.fragment`'s sections change — there's no
automated link between the two, so a stale entry here won't be caught by
anything. Grouped to mirror the fragment's own section comments
(Mountify/OverlayFS, Kallsyms, Performance, ZRAM, I/O Scheduler, F2FS, TCP
BBR, IP Set, IPv6 NAT, Networking extras, debug overhead), not a flat list
— easier to scan on the Telegraph page.

**`LTO_DISPLAY`** — maps `LTO_MODE` raw values ("NONE"/"THIN"/"FULL", from
the workflow's LTO choice input) to their display form on the Telegraph
Overview block.

**`html_escape()`** — text-node escaping for Telegram HTML `parse_mode` —
only `& < >` matter here (no attribute context); order matters, `&` must
go first or it would double-escape the entities just inserted for `<` and
`>`.

**`html_escape_attr()`** — same as `html_escape()` plus quote-escaping, for
use inside an `href="..."` attribute value.

**`kernel_source_repo()`** — single source of truth (within `caption.py`)
for the kernel source repo naming convention — `LuminaireKernel-{version}`,
e.g. `LuminaireKernel-6.1`. Matches `download/make.sh` and
`.github/workflows/kernel-source.yml`, which each define this pattern
independently on the shell side (different domain, build-time vs
caption-time, not worth threading through env just to unify). Used by both
`build_blocks()` (zip caption) and `build_telegraph_content()` (Telegraph
Overview) so the two never drift apart from each other at least.

**`build_blocks()`, mountless-engine resolution** — only three possible
values here: `None` (user didn't pick a mountless engine), or the display
name of whichever one they picked. Unlike the `TOGGLE_ADDON_ORDER` lines
below, there's no N/A state to show — an unsupported-for-this-kernel-
version mountless addon just falls back to "None" the same as never
having been selected, since the mountless engine is a single either/or
choice, not an availability flag.

**`build_blocks()`, toggle addon status** — `"N/A"` means not backported
for this kernel version yet, distinct from a user's own `"Disable"`.

**`build_blocks()`, core-patch status** — no Disable state here: these are
never user-toggled, only `"Active"` (this kernel version has the backport)
or `"N/A"` (it doesn't yet).

**`build_blocks()`, `block_core_patch`** — the whole block is omitted when
nothing in it is Active — an all-N/A Core-Patch section (e.g. neither BORE
nor ADIOS backported yet for this kernel version) isn't useful
information, just noise. `main()`'s `caption_group` join already drops
`None` blocks.

**`build_telegraph_content()`** — builds the Node-array content for a
per-release Telegraph page (see Telegraph's Content Format:
https://telegra.ph/api#Content-format). Three sections:
- "Overview": release-wide build facts (Kernel/Source/Toolchain/LTO).
  Source is derived from `KERNEL_VERSION` (repo is always
  `LuminaireKernel-{version}` — see `download/make.sh`). Toolchain/LTO
  come from `telegram.sh`'s per-variant JSON (`compiler_string`/
  `lto_mode` — see `channel_post.sh`'s "first non-empty wins" parsing)
  rather than a per-variant source, because they're both backed by single
  global workflow inputs (`LTO_MODE`) or a value derived from one
  (`COMPILER_STRING` from the one `CLANG_VARIANT` used release-wide) —
  verified against `build.yml` before relying on that, not assumed.
- "Core Features": `FRAGMENT_FEATURES`, grouped exactly like the dict's
  categories, always-on regardless of build.
- "Luminaire Features": every `CORE_PATCH_ORDER` entry (ADIOS, BORE) —
  always-on, no toggle; check-mark if this kernel version has the
  backport, minus-sign (not X) if not, since there's no user Disable
  state for these, only a per-version rollout gap.
- "Optional Add-ons": every `TOGGLE_ADDON_ORDER` entry as a single
  monospace Feature/Status table (check/X) reflecting *this* build. A
  real HTML `<table>` isn't an option — Telegraph's allowed tag set has no
  table/tr/td, so this is a `<pre><code>` block with manually
  column-aligned text instead, replacing the old enabled/disabled two-list
  split.

Returns a plain Python list (`json.dumps`'d by the caller), not a JSON
string itself.

**`build_push_caption()`** — caption for the plain push-event notify
(`.github/workflows/notify.yml`), distinct from `build_blocks()`/
`build_channel_caption()` above (those are for release/build posts, still
MarkdownV2 — only the push notify uses HTML). Layout follows the redesign
from commits `b69f6bf`/`8a860ed` (header line, Branch in inline code,
Author linked, Title/Message as boxed blocks, Commit link as the closing
line) — only the markup language changed from MarkdownV2 to HTML, the
structure itself didn't. Uses HTML `parse_mode` instead of MarkdownV2: HTML
only needs `& < >` escaped in text nodes, so a stray unescaped character
can't silently break the whole message the way one missed MDv2 special
char can.

**`build_push_caption()`, `title_block`** — `<pre><code class="language-X">`
is how Telegram HTML gets the small "language" label in the corner of the
box — the same visual Telegram gives a MarkdownV2 fenced block tagged
` ```X ... ``` ` (what `b69f6bf` originally used). A plain `<pre>` alone
doesn't carry that label.

**`build_push_caption()`, body budget** — the body block is budgeted
against what's left after `head_full` + `footer` + the fixed wrapper tags,
so `truncate()` never has to cut inside a `<pre>`/`<code>` tag itself —
only the escaped body shortens.

**`build_channel_caption()`** — `variant_links`: dict
`{ "VANILLA": "https://t.me/c/...", "RESUKISU_SUSFS": "...", ... }`.
`variant_versions`: dict `{ "RESUKISU": "v4.1.0 (35002/2)",
"SUKISU_SUSFS": "4.1.2 (40819/2)", ... }` — optional. Keys match
`variant_links`' keys exactly (including the `_SUSFS` suffix where
applicable). All three forks resolve a version string (see
`resukisu.sh`/`sukisu.sh`/`ksunext.sh`'s "Version string" step); a fork
only lacks an entry if that step itself failed to resolve anything. Only
variants present in `variant_links` will be listed.

**`build_channel_caption()`, "What's Inside?" link** — links out to a
per-release Telegraph page (built fresh per release, never reused — see
`build_telegraph_content()`) listing every always-on fragment feature plus
every addon's Enable/Disable status for this build. `FEATURES_URL` is
populated by `channel_post.sh` after calling `telegraph_page.py`; left
empty if that call failed (Telegraph API down, etc.), in which case this
falls back to plain text pointing at the Add-ons block already present in
the zip's own caption — chosen over pointing into the zip's contents
directly, since the archive itself carries no bundled feature manifest.

**`build_channel_caption()`, download links** — variant lines rendered as
a blockquote (each line prefixed with `>` per Telegram MarkdownV2's
blockquote syntax); the "Download" heading itself stays outside the quote.
A bare `>` blank line is inserted between entries — still part of the same
quote (the left bar stays unbroken), but gives each link more vertical
breathing room so adjacent links aren't a mis-tap risk on small screens.

**`build_channel_caption()`, changelog block** — manual input, optional,
capped so it can't crowd out the rest of the caption if someone pastes
something huge. Rendered as a code block, same style as the group
caption's Root-solution/Add-ons blocks, instead of plain bold text.

**`build_channel_caption()`, traceability line** — commit + workflow run
that produced this post. Kept tight against the changelog block (single
newline, no blank-line gap) when a changelog is present, since both are
"fine print" — everything else still gets the normal blank-line spacing.

**`main()`** — push-notify mode: `caption.py push <output_file>` —
separate from the release/build mode below (2 positional args, no
subcommand), since it's a different caller (`notify.yml`) with a different
env-var shape (`BRANCH`/`AUTHOR`/`COMMIT`/`URL`/`TITLE`/`BODY` vs. the
build-metadata vars `build_blocks()`/`build_channel_caption()` expect).

**`main()`, channel caption** — built from `VARIANT_LINKS_JSON` (provided
by `channel_post.sh`).

---

## `release/telegram/channel_post.sh`

**Purpose of this file**: aggregates all variant links and sends a single
photo post to the channel. Called from the `notify-channel` job after all
builds have finished.

Runs standalone (`bash release/telegram/channel_post.sh`) from
`notify-channel`, unlike `telegram.sh` which is sourced from `build.sh`'s
`run_release()` — so `log`/`warn`/`error`/`retry()` aren't in scope until
sourced explicitly here.

**Variant JSON parsing** — parses all variant JSON files, extracting
links, `linux_ver`, `kernel_version`, and (where present) `ksu_version`
per variant. `compiler_string`, `lto_mode`, `skipped_addons`,
`applied_luminaire`, and `skipped_luminaire` are release-wide constants
(single global workflow inputs, not per-variant — see `telegram.sh` where
they're written), so the first non-empty value wins, same as
`linux_ver`/`kernel_version`.

`LINKS_DIR` env var points to a dir with `*.json` files, each shaped like
`{"variant": "VANILLA", "link": "https://t.me/c/..."}`.

**Missing-variants diff** — compares variants selected for this run
against variants that actually produced a download link. Release mode is
only ever triggered after a Build run already confirmed every selected
variant is fine — so if a variant that was selected here doesn't have a
link, its matrix job failed unexpectedly for *this* run (e.g. a checkpoint
pin expired between Build and Release, or an upstream regression). That's
exactly the situation a Release-mode failure should stay loud about
instead of quietly shipping a partial channel post — so this hard-fails
the whole job rather than posting whatever succeeded. Skipping the channel
post on any mismatch also means a stale manual `CHANGELOG` mention of the
failed variant never reaches the channel in the first place.

**Telegraph Features page creation** — never fails the job:
`telegraph_page.py` always exits 0 and prints an empty line on failure
(missing token, API down, retries exhausted) — `caption.py`'s
`build_channel_caption()` falls back to plain text pointing at the zip
caption's Add-ons block when `FEATURES_URL` is empty.

---

## `release/telegram/telegram.sh`

**Thread routing (`RUN_MODE` → `TARGET_THREAD_ID`)** — picks the
destination topic from `RUN_MODE`. Warm Run mode never reaches this script
(`build.sh` exits before `run_release`), and Dry Run returns above before
this point — so only Build/Release are valid here, anything else is a
misconfiguration, not a silent no-op. Build mode has one topic per kernel
version (`TELEGRAM_THREAD_ID_BUILD_BY_VERSION` in `config.sh`, keyed by
`$KERNEL_VERSION`) instead of a single shared topic.

**`KERNEL_VARIANT_VERSION`** — each fork resolves its own version string
in its integration script (`resukisu.sh`/`sukisu.sh`/`ksunext.sh`,
"Version string" step) and exports it via `$GITHUB_ENV` — this picks the
one matching this build's fork.

**Variant link save** — the channel post itself is handled by the
`notify-channel` job (Release mode only); this just writes this variant's
link JSON for that job to aggregate later.

---

## `kernel/config/defconfig.sh`

**Purpose of this file**: applied after `gki_defconfig`, via
`scripts/config`.

**LTO fallback (`else` branch)** — covers both the explicit `"NONE"` value
and any unrecognized value — `NONE` is the safe fallback either way, only
the log line differs.

**LZ4KD block** — same class of bug as `CONFIG_SCHED_BORE` (see
`bore.sh`) — a `gki_defconfig` text-append alone isn't reliably surviving
to the final compiled kernel. On-device verification showed
`crypto/lz4k.o` and `crypto/lz4kd.o` both compile and register in
`/proc/crypto` (so the Kconfig symbol, Makefile `obj-y` line, and patch
apply are all correct at patch-apply time), yet
`CONFIG_CRYPTO_LZ4K`/`LZ4KD` are absent from `/proc/config.gz` on the
flashed device and `zcomp.c`'s `IS_ENABLED(CONFIG_CRYPTO_LZ4K)`
backend-list guard evaluates false, so zram never offers `lz4k`/`lz4kd` as
a `comp_algorithm` option. Root cause not pinned down (same as BORE).
Enforcing here too, directly on the post-merge `.config` via
`scripts/config` (same proven mechanism as `LTO_MODE`/BBG), as a second,
more direct path. The `LZ4K_*`/`LZ4KD_*` symbols are plain `tristate`
(select-only, no prompt) in `lib/Kconfig` — `scripts/config` bypasses
Kconfig's `select` resolution entirely, so they need to be forced
explicitly too, not just the crypto/Kconfig-level `CRYPTO_LZ4K`/`LZ4KD`
symbols that normally `select` them.

`CONFIG_ZRAM=m` by default (stock `gki_defconfig`) — zram then ships as a
separate `zram.ko`, loaded on this device from the read-only,
dm-verity-protected `system_dlkm` partition (confirmed via `cat
/proc/mounts`), not the boot ramdisk. AnyKernel3's repack flow only
touches `boot.img`, so a rebuilt `zram.ko` with LZ4K/LZ4KD support never
reaches the running device no matter how correct the compile is — the
stock `system_dlkm` `zram.ko` keeps loading every boot. Forcing `=y` here
builds zram directly into `Image` instead (same as WireGuard/lib/zstd),
which *does* ship via the normal AK3 flash — same fix other SM8750 GKI
kernel builders (e.g. ox1d3x3/Op13_Susfs_kernel) use for this exact
reason. Only touched when LZ4KD is actually enabled — no reason to change
zram's module-ness on builds that don't need it.

**`ZRAM_DEF_COMP_LZ4KD` forcing** — the `lz4kd.patch` itself already flips
the `ZRAM_DEF_COMP` choice's default from `ZRAM_DEF_COMP_LZORLE` to
`ZRAM_DEF_COMP_LZ4KD` (so lz4kd becomes the kernel's own boot-time
default, zero userspace steps needed) — but `luminaire.fragment`
unconditionally forces `ZRAM_DEF_COMP_LZ4=y` earlier in this same script
for builds that don't have LZ4KD, which otherwise silently overrides the
patch's intent here too. Forced back to LZ4KD explicitly so it doesn't
require a manual `echo lz4kd > comp_algorithm` after every boot.
`scripts/config` edits `.config` as flat text — it has no notion of
Kconfig `choice` groups, so `--enable` on one choice member does NOT
automatically clear sibling members the way real Kconfig evaluation would.
`luminaire.fragment` already set `ZRAM_DEF_COMP_LZ4=y` earlier in this
script; without explicitly disabling it here too, both ended up `=y`
simultaneously and LZ4 (set first) kept winning on-device.

**BBG block** — BBG requires `baseband_guard` in `CONFIG_LSM` — patched
here because `.config` is not available yet when `bbg.sh` runs (before
`make defconfig`).

---

## `kernel/ksu-shared/fix_namespace.py`

**Idempotency check** — both markers present means either the main patch
applied hunk #1 successfully (after `blk.h` pre-patch removal in
`susfs.sh`), or a previous run of this fallback already injected them.
Either way, nothing left to do.

---

## `kernel/addons/zeromount/inject_namei.py`

**Purpose of this file**: inject ZeroMount hooks into `fs/namei.c`.
Handles `namei.c` injection for every ZeroMount build (RESUKISU, SUKISU,
KSUNEXT — ZeroMount requires SuSFS, so VANILLA is never a valid combo, see
`zeromount.sh`), replacing the `namei.c` hunks from the ZeroMount patch,
which are diffed against a SuSFS-patched baseline and mis-apply on a
non-SuSFS tree (see `strip_namei_hunk.py` for the full explanation). The
ZeroMount patch is pre-stripped of its `namei.c` hunks before being
applied, so this worker is always the sole authority for `namei.c`
injection.

All anchors are matched against real, unpatched upstream `fs/namei.c`
(`chainonyourdoor/LuminaireKernel-6.1`, `android14-6.1-live`) — they don't
depend on SuSFS or any KSU fork having touched the file first, so this
applies identically and correctly regardless of variant or patch order
(baseline-agnostic by design, even though SuSFS is required at the addon
level — see `zeromount.sh`).

**Include injection** — `#include <linux/zeromount.h>` goes after the last
file-local include, before the function bodies start.

**`GETNAME_ANCHOR`** — in `getname_flags()`, right before the final
`return result;` of its non-empty-path path. Anchored on the three-line
block immediately preceding that return, which is unique to this function
(`getname_kernel()` also calls `audit_getname(result)` but with a blank
line before its return and without the two preceding `result->` assignments).

**Permission-check short-circuit** — identical block injected at the top
of both `generic_permission()` and `inode_permission()`, each anchored on
the first real statement of that specific function (unique per function,
so the two can't cross-match each other).

---

## `kernel/addons/zeromount/inject_readdir.py`

**Purpose of this file**: inject ZeroMount hooks into `fs/readdir.c`.
Handles `readdir.c` injection for every ZeroMount build (RESUKISU, SUKISU,
KSUNEXT — ZeroMount requires SuSFS, so VANILLA is never a valid combo, see
`zeromount.sh`), replacing the `readdir.c` hunks from the ZeroMount patch
which require SuSFS context to apply cleanly. The ZeroMount patch is
pre-stripped of its `readdir.c` hunk (via `strip_readdir_hunk.py`) before
being applied, so this worker is always the sole authority for
`readdir.c` injection.

**`find_getdents_non_compat()`** — returns the line index of
`SYSCALL_DEFINE3(getdents, ...)` that is NOT inside `#ifdef
CONFIG_COMPAT`. Only the non-compat variant is wanted.

**`SEARCH_WINDOW`** — search within a generous window after
`getdents_idx` — dynamic enough to handle upstream `readdir.c` growing
without hardcoded line limits.

**Injection sequence** — 1) `#include <linux/zeromount.h>`. 2) inject
`initial_count` + `MAGIC_POS` check after the `fdget_pos` block (pattern:
`fdget_pos` line followed by `if (!f.file)`). 3) inject the `MAGIC_POS`
early-exit before `iterate_dir` and `zeromount_inject_dents` after it. 4)
inject the `zm_out:` label before `fdput_pos(f)`. Each window is
recalculated after every insert since line indices shift.

---

## `kernel/addons/zeromount/strip_namei_hunk.py`

**Purpose of this file**: strip the `fs/namei.c` hunks from the ZeroMount
patch.

The ZeroMount patch's `fs/namei.c` section is diffed against a SuSFS-
patched baseline — its first hunk's unchanged context includes `#ifdef
CONFIG_KSU_SUSFS_UNICODE_FILTER` / `extern bool
susfs_check_unicode_bypass(...)`, which only exists once SuSFS has already
been patched in. Applying it to a non-SuSFS tree means that context can't
match, and `--fuzz=3` will still force a match rather than fail outright —
landing the later hunks (the `generic_permission()`/`inode_permission()`
permission-check injections) outside the actual function bodies,
producing "undeclared identifier 'inode'/'mask'" compile errors. Confirmed
via a VANILLA build failure (`fs/namei.c:833`) while the same patch
applied cleanly on all three SuSFS-patched variants in the same run —
VANILLA (and any non-SuSFS variant) is no longer a supported combo for
this addon at all (see `zeromount.sh`), but the failure mode that led here
is still the reason this strip exists.

`inject_namei.py` handles `fs/namei.c` via anchor-based injection instead
(anchors are baseline-agnostic real function bodies), so the patch hunks
are not needed. This mirrors `strip_readdir_hunk.py`, which strips the
same-root-cause-affected `fs/readdir.c` hunk.

This script strips the `namei.c` diff section from the patch file
in-place before it is applied, guaranteeing zero hunk failures and zero
silent mis-application.

---

## `kernel/addons/zeromount/strip_readdir_hunk.py`

**Purpose of this file**: strip the `fs/readdir.c` hunk from the
ZeroMount patch.

The ZeroMount patch contains a `readdir.c` hunk that anchors on
`CONFIG_KSU_SUSFS_SUS_PATH` context, causing it to fail on a non-SuSFS
tree (VANILLA, or any variant with SuSFS disabled — neither is a
supported combo for this addon, see `zeromount.sh`). `inject_readdir.py`
handles `readdir.c` via anchor-based injection instead, so the patch hunk
is not needed regardless.

This script strips the `readdir.c` diff section from the patch file
in-place before it is applied, guaranteeing zero hunk failures.

---

## `kernel/addons/zeromount/fix_taskmmu.py`

**Purpose of this file**: fix a scope bug in `task_mmu.c`'s show_map_vma
injection.

ZeroMount now requires SuSFS unconditionally (`build.sh`'s addon conflict
matrix errors out before this ever runs on a non-SuSFS tree — see
`run_addons()`), so this only has to handle the with-SuSFS scope bug.
There used to be a second "broken_vanilla" case here for non-SuSFS trees
(`zeromount_spoof_mmap_metadata()` landing inside the `if(!mm){}` block
instead of `if(file){}`); it's gone along with non-SuSFS support.

**`broken`/`fixed` patterns** — the zeromount call landed after the
`SUS_KSTAT` block but still inside `if(file){}` scope; `fixed` moves it
back outside.

**Fallback branch** — `zeromount_spoof_mmap_metadata` present but not
matching the known broken pattern means either already fixed by a
previous run (idempotent, not an error) or the surrounding SuSFS code
shifted upstream (a real problem, but indistinguishable from "already
fixed" by string match alone). Exits 0 either way; if this masks a real
upstream drift, the actual compile error downstream will surface it.

---

## `kernel/addons/rekernel/inject.py`

**Purpose of this file**: Re:Kernel source injector for android14-6.1.
Injects a Netlink server into three kernel files: `drivers/android/
rekernel.h` (new file — Netlink server impl), `drivers/android/binder.c`
(binder_transaction hooks), `drivers/android/binder_alloc.c` (async
buffer full hook), and `kernel/signal.c` (signal hook). Idempotent: checks
for a marker before injecting.

**`inject_after_any()`** — tries multiple anchors in order; returns on
first match.

**`inject_include_fallback()`** — fallback: inserts `include_line` after
the last `#include` directive found within the first 120 lines of the
file.

**`inject_include()`** — injects `include_line` after the first matching
local include anchor, falling back to the last-`#include`-in-header-
section method.

**`patch_binder_c()`, partial-injection guard** — a partial injection
(e.g. only the txn hook landing) would still contain the "Re:Kernel"
marker via its own comment, so `rekernel.sh`'s downstream `grep -q
"Re:Kernel" binder.c` guard can't distinguish full from partial injection.
Treated as fatal here instead, matching the fail-fast behavior of the
other `patch.py` scripts in this repo.

---

## `kernel/addons/bbrv3/enforcer.py`

**`ENFORCER_BLOCK`** — re-asserts bbr3 as
`net.ipv4.tcp_congestion_control` a handful of times during early boot so
a vendor init script writing over it doesn't stick (confirmed root cause
on MediaTek devices: `/vendor/etc/init/*.rc` scripts running at `on
early-init`, e.g. `write .../tcp_congestion_control bic`). Stops after
`LUMINAIRE_BBR3_ENFORCE_TRIES` — this only needs to win the boot-time
race, not fight the user's own later choice (e.g. manually switching
algorithm via a kernel manager app). Lives inside `net/ipv4/tcp_cong.c`
rather than a new file because `tcp_set_default_congestion_control()`
isn't `EXPORT_SYMBOL`'d — it's only callable from within the same
translation unit.

---

## `kernel/core/compiler_string/patch.py`

**Purpose of this file**: patches `mkcompile_h`'s `CC_VERSION`/
`LD_VERSION` lines to produce a clean compiler string.

`mkcompile_h` is called by the kernel Makefile — the exact positional arg
number varies by kernel version/convention: GKI 6.1-style (trimmed):
`scripts/mkcompile_h "$(UTS_MACHINE)" "$(CONFIG_CC_VERSION_TEXT)" "$(LD)"`
→ `CC_VERSION="$2"`. Older/mainline-style (e.g. 5.10's GKI tree, still
close to upstream `scripts/mkcompile_h`): TARGET/ARCH/SMP/PREEMPT/
PREEMPT_RT/CC_VERSION/LD as `$1..$7` → `CC_VERSION="$6"`. The regex
matches `CC_VERSION="$N"` for any N so this doesn't need a per-kernel-
version special case — confirmed both patterns exist in the wild
(android14-6.1: `$2`, android12-5.10: `$6`).

`CONFIG_CC_VERSION_TEXT` is baked at defconfig time from raw `clang
--version` output — `KBUILD_COMPILER_STRING` is never used here.
`CC_VERSION` is hardcoded to the clean string directly. `LD_VERSION`
reads raw `ld.lld -v` output with the full LLVM commit URL; it's replaced
with a clean extraction that yields `"LLD X.Y.Z"` only. Result:
`LINUX_COMPILER = "Cirrus Clang 23.0.0, LLD 23.0.0"`.

**Idempotency check** (same convention as `module_bypass/patch.py`) —
without it, re-running the patcher against an already-patched file hits a
false "partial match": the CC pattern (`CC_VERSION="$2"`) no longer
matches since it's now a literal string, but the LD pattern
(`LD_VERSION=$()`) still matches its own already-patched replacement
(`clean_ld` also starts with `LD_VERSION=$(`) — `cc_replaced=False,
ld_replaced=True`, which trips the fatal partial-match abort below even
though the file is actually fully and correctly patched already.

**Paren-depth tracking for `LD_VERSION=$(...)`** — tracks paren depth to
find where this multi-line assignment actually closes. Must ignore
parens inside single quotes — the sed pattern `'s/(compatible with
[^)]*)//'` has literal `(` `)` chars that aren't real shell grouping.
Naive raw counting broke on android12-5.10's `mkcompile_h`, where that
whole quoted sed clause sits on the same line as the opening `"$("`:
depth hit 0 after just that one line (the quoted parens happened to
balance out), leaving the real closing line (`" | sed '...')"`)
unconsumed as an orphan — which starts with `|`, causing a shell syntax
error at runtime. android14-6.1's version has the sed clause on its own
separate line, so the same naive counting happened to land on the right
line there by coincidence, masking the bug until this kernel version.

**Partial-match abort** — writing a half-patched file would produce an
inconsistent compiler string (e.g. CC patched but LD still raw LLVM URL
output). Treated as fatal so the issue is visible rather than silently
wrong.

---

## `kernel/core/openssl3_compat/patch.py`

**Purpose of this file**: fixes a half-applied OpenSSL-3 compat backport
in `certs/extract-cert.c`. `key_pass`'s declaration is gated behind
`#ifdef USE_PKCS11_ENGINE`, but nothing in the file ever defines that
macro, and the PKCS#11 branch further down uses `key_pass` completely
unguarded. Result on any OpenSSL 3.x toolchain: `key_pass`'s declaration
gets compiled out while its usage doesn't, i.e. "use of undeclared
identifier 'key_pass'".

Fix: define `USE_PKCS11_ENGINE` whenever the ENGINE API is actually
available. This is safe for this file specifically because
`ENGINE_load_builtin_engines()`/`ENGINE_by_id()`/etc. a few lines down are
already called unconditionally (not gated by this macro at all) — so if
ENGINE support isn't there, this file was already broken before this
patch touches it.

---

## `kernel/ksu-shared/ksunext/branding.py`

**Purpose of this file**: injects Luminaire branding into KernelSU-Next's
Kbuild version tag.

KernelSU-Next's Kbuild has no `KSU_VERSION_FULL` (unlike ReSukiSU/
SukiSU-Ultra) — it only builds `KSU_VERSION_TAG` from `KSU_GIT_TAG` (or a
hardcoded fallback when not a git repo), so that's the anchor here.

Kbuild consumes `KSU_VERSION_TAG` unquoted in `ccflags-y` (just the raw
string with no surrounding single quotes), so a space in the branding
suffix breaks shell tokenization of `ccflags-y` and clang chokes on the
second half as a bogus input file. Both `ccflags-y` lines are wrapped in
single quotes to make the whole define one token — same fix already
applied in `resukisu/branding.py` and `sukisu/branding.py`.

---

## `release/telegram/telegraph_page.py`

**Purpose of this file**: creates a fresh Telegraph page for this release
(never reused across releases — reusing one page would let historical
Telegram channel posts silently drift, since anyone scrolling back and
clicking an old "Features" link would see whatever the page currently
says, not what was true when that post went out).

This is a standalone script (not sourced) so it can be called once from
`channel_post.sh`, before the channel caption is built, with its stdout
captured directly as the page URL. Never causes the build/post to fail:
on any error it prints an empty line to stdout and exits 0 — the caller
(`channel_post.sh`) treats an empty result as "no Features link, fall
back to the zip caption's Add-ons block" (see `build_channel_caption()`
in `caption.py`).

**`create_page()`** — no explicit `author_name` here — omitting it makes
Telegraph fall back to the account's own default `author_name` (set once
at `createAccount` time), instead of overriding it per-page with a
hardcoded value.

---

## `kernel/addons/lz4zstd/lz4zstd.sh`

**Purpose of this file**: bumps ZRAM compression to LZ4 1.10.0 + ZSTD
1.5.7. Patch source: https://github.com/mrcxlinux/kernel_patches
(`zram/`). Pure library version bump — no Kconfig involved, this just
replaces the vendored `lib/lz4` and `lib/zstd` source with newer upstream
releases. Non-fatal on failure (warn, not error): this is a compression-
ratio/speed optimization, not a correctness-critical patch — a build
without it just keeps whatever LZ4/ZSTD version this kernel branch
already ships.

**LZ4 rename-hunk problem** — the LZ4 patch contains 3 git-style rename
hunks (`fs/f2fs/lz4armv8/{lz4accel.c,lz4accel.h,lz4armv8.S}` →
`lib/lz4/lz4armv8/...`) that assume an old f2fs-local copy already exists
pre-patch. This GKI tree never carried that dir, so all 3 renames fail no
matter what — confirmed by diffing `lib/lz4/lz4_compress.c` etc. against
the patch's own assumed pre-image (byte-identical match), which rules out
a source-mismatch explanation. These 3 files are NOT optional: the
patch's new `lib/lz4/lz4.h` unconditionally `#include
"lz4armv8/lz4accel.h"` (no arch guard at the include site — the guard
lives inside `lz4accel.h` itself), so a missing `lz4accel.h` is a hard
build break (fatal on every arch, not just arm64), confirmed by an actual
CI failure before this was fixed. `lz4armv8.S` is also a binary git-diff
(`patch` can't apply those at all). None of the 3 are hosted standalone
upstream except `lz4armv8.S`, so `lz4accel.c`/`.h` are reconstructed here
verbatim from their original upstream commit
(pascua28/android_kernel_samsung_sm8250@0ac937e "Import arm64 V8 ASM lz4
decompression acceleration") and pre-staged directly at their post-patch
path, bypassing the patch tool's rename hunks entirely for all 3 files.
`lz4accel.h`'s `#else` branch makes it safe to include unconditionally on
any arch (stubs out to a no-op when not arm64+NEON).

**Why the apply isn't gated behind a blanket dry-run** — previously
gated the whole apply behind one blanket `--dry-run --forward` check on
the entire (40+ file) patch, which treated it as all-or-nothing: the
(then-unhandled) rename hunks failing in the dry-run caused it to skip
the *entire* patch, including ~13 other files (the actual 1.10.0
algorithm source) that apply cleanly on their own. Fixed by applying
directly — `patch` (unlike `git apply`) already continues past a failed
hunk/file instead of aborting the rest — and verifying success via a real
version marker in the patched source, not exit code alone (patch exits
nonzero even when only the now pre-staged, harmless rename hunks fail).

**Why ZSTD is a full source replacement, not a patch** — the mrcxlinux
`002-zstd.patch` targets ZSTD 1.5.7 but assumed a pre-image that no
longer matches this tree's 1.4.10 source closely enough — confirmed by
diffing both against upstream, several releases apart — so nearly every
hunk rejected outright, not just a rename. A patch can't bridge that gap
reliably, so instead of patching, the full `lib/zstd` source tree (+
`include/linux/zstd*.h`) is fetched directly from `torvalds/linux` tag
`v6.15`, which ships ZSTD 1.5.7 verbatim, replacing the vendored files
wholesale. Verified compatible before wiring this up: v6.15's
`lib/zstd/Makefile` keeps the same `CONFIG_ZSTD_COMPRESS/DECOMPRESS/
COMMON` Kconfig symbols (only adds two new `.o` entries), and
`include/linux/zstd.h`'s v6.15 diff is purely additive — no existing
wrapper function signature changed, so other in-tree callers (f2fs, zram,
etc.) keep compiling untouched.

One real incompatibility was found and is patched post-copy: v6.15's
`common/mem.h` includes the generic `<linux/unaligned.h>`, which doesn't
exist yet in this 6.1 tree (only the arch-specific `<asm/unaligned.h>`
does) — left as-is this is a fatal missing-header build break. (A
separate `intptr_t` typedef removed from `common/zstd_deps.h` in v6.15
was checked too: it's gated behind `ZSTD_DEPS_NEED_STDINT`, which nothing
in this file set defines, so that branch is dead code either way — no fix
needed there.)

**`apply_lz4zstd_patch()`, `touched_files`** — files this patch touches,
so they can be cleanly reverted if the apply doesn't actually land,
instead of leaving a half-patched mix of old/new source behind.

**`apply_lz4zstd_patch()`, marker verification** — verifies with real
evidence (a version marker from the patched source) rather than trusting
exit code alone, since `patch` exits nonzero even when only the
pre-staged, harmless rename hunks failed.

**`ZSTD_FILES`** — the complete v6.15 `lib/zstd` tree plus its public
`include/linux/zstd*.h` headers — anything not listed here is left
untouched.

**`replace_zstd_source()`, staging dir** — the whole fetch is staged in a
scratch dir first and the real tree is only touched once every file is
confirmed downloaded, so a mid-fetch network failure can't leave a
half-1.4.10/half-1.5.7 mix behind.

**`replace_zstd_source()`, `mem.h` sed fix** — compat fix: this 6.1 tree
predates the generic `<linux/unaligned.h>` wrapper header that v6.15's
`mem.h` switched to — only the arch-specific `<asm/unaligned.h>` exists
here (see the ZSTD incompatibility note above).

---

## `kernel/{android12-5.10,android13-5.15,android14-6.1}/ksu/susfs/susfs.sh`

**Purpose of these files**: SuSFS — shared apply logic (any KSU fork),
one per kernel version. Repo: https://gitlab.com/simonpunk/susfs4ksu.
Nearly identical across all three versions (branch names/patch filenames
swap per version); documented once here.

**SuSFS pin resolution** — SukiSU-Ultra needs an exact commit paired with
a matching susfs4ksu commit (community-verified combo, not just "old
enough"). ReSukiSU is generally compatible with SuSFS's branch tip, so
it isn't pinned as tightly. `kernel/checkpoint/scout.sh` exports the
right `*_REF` beforehand.

**KernelSU-Next (KSUNEXT) pairing** — uses pershoot's KernelSU-Next fork
(dev-susfs branch, see `kernel/ksu-shared/ksunext/ksunext.sh` — shared
across all kernel versions) for its own SUSFS-compatible hooks, but the
SuSFS *source* itself comes from simonpunk/susfs4ksu's own `-dev` branch
— verified directly against source that every `susfs_*` symbol
pershoot's fork calls but doesn't define itself is already provided by
simonpunk's official `susfs_def.h`/`susfs.h` (byte-identical across
kernel versions).

**Missing kernel-patch guard** — doesn't return/exit when the patch file
is missing — a missing/renamed patch file upstream (this has happened
before) must not skip the Kconfig injection and `CONFIG_KSU_SUSFS`
enablement further down. `fix_namespace.py`'s own anchor-missing check
will still catch it hard if the underlying source structure changed too.

**`blk.h` pre-patch/post-patch workaround** — sublevel >= 157 adds
`#include <trace/hooks/blk.h>` to `namespace.c`, which shifts context and
causes hunk #1 to fail. It's removed temporarily so the patch can match,
then restored after. Traced to upstream commit `60dddcb8f9` (Wang
Jianzheng, 2024-06-07, `kernel/common fs/namespace.c`). That commit
landed on the android14-6.1 history specifically — on android12-5.10 and
android13-5.15, this workaround is gated to `KERNEL_VERSION = "6.1"` only
(their own SUBLEVEL numbering doesn't correspond to the same commit),
until someone actually checks whether/where those versions' `namespace.c`
needs the same treatment (don't assume — verify against the real
source). The restore step verifies the restore actually landed — if the
`"internal.h"` anchor was itself missing/renamed upstream, `sed` would
silently no-op and blk.h would be lost permanently without anyone
noticing until link time.

**android12-5.10/android14-6.1 historical NOTE** (present in those two
files, since removed from android13-5.15's copy) — an earlier
pershoot/susfs4ksu fork used to ship a second patch
(`kernel_patches/60_scope-minimized_manual_hooks.patch`) that scoped down
KernelSU-Next's manual hooks so they wouldn't collide with its
`syscall_hook_manager` wiring. That patch — and `syscall_hook_manager`
itself — is gone as of the fork's current dev-susfs branch: the branch
now ships the manual-hook/SuSFS integration directly in KernelSU-Next's
own source (`kernel/feature`, `kernel/hook`, `kernel/selinux`, etc.), so
there's nothing left to apply here for KSUNEXT beyond the standard
simonpunk/susfs4ksu patch above. Confirmed via on-device check
(2026-07-05): `CONFIG_KSU_SUSFS` and its sub-options compile in, and
dmesg shows the integration's sucompat log line firing at runtime. If
pershoot's fork restructures again and SuSFS stops working on KSUNEXT,
check `kernel_patches/` in that fork first before assuming this note is
still accurate.

---

## `kernel/ksu-shared/ksunext/ksunext.sh`

**Purpose of this file**: root solution — KernelSU-Next. Repo:
https://github.com/KernelSU-Next/KernelSU-Next.

**`KSU_DIR`** — `setup.sh` clones into `${GKI_ROOT}/KernelSU-Next` and
symlinks `drivers/kernelsu -> KernelSU-Next/kernel`, unlike ReSukiSU/
SukiSU-Ultra's `setup.sh` which both produce a `"KernelSU"` dir directly —
`KSU_DIR` here is intentionally different from `resukisu.sh`/`sukisu.sh`
for this reason.

**SuSFS fork selection** — official KernelSU-Next has no SUSFS-compatible
hook API on its dev branch (see `susfs.sh`) — pershoot's fork keeps a
dev-susfs branch that does, paired with their own susfs4ksu fork. The
maintainer flags this fork as not production-ready; tracked like any
other candidate via `kernel/checkpoint/scout.sh`.

**Version string computation** — official KernelSU-Next's Kbuild:
`KSU_VERSION = 30000 + rev-list --count HEAD`, `KSU_VERSION_TAG = git
describe --tags --abbrev=0` at HEAD (fallback `v0.0.1`). Simple and
purely local, like ReSukiSU's formula.

pershoot/KernelSU-Next's dev-susfs fork (used when `SUSFS_ENABLED`)
computes both from a `BASE_COMMIT` instead of raw HEAD — the merge-base
between HEAD and `origin/<branch-with-suffix-stripped>` (falls back to
`origin/main`, then HEAD itself) — so fork-specific commits on top of
upstream don't inflate the version number. Replicated here rather than
simplified to raw HEAD, since that would give a different number than
what's actually compiled. This fork is flagged not-production-ready
upstream, so treat this version string as unverified until a real build
confirms it.

**Kconfig section** — no `CONFIG_KPM` here — KernelPatch is a
SukiSU-Ultra/ReSukiSU feature, KernelSU-Next's Kconfig doesn't declare
it.

---

## `kernel/addons/kasumi/kasumi.sh`

**Purpose of this file**: addon — Kasumi (path manipulation/hiding LKM),
by Anatdx. Repo: https://github.com/Anatdx/Kasumi.

Kasumi is NOT an in-tree kernel patch — it's an out-of-tree LKM
(`kasumi_lkm.ko`) built separately against a prepared kernel tree (needs
`Module.symvers`, which only exists after the main kernel build
finishes). This script only clones the source; the actual module compile
happens in `kernel/addons/kasumi/postbuild.sh` (`run_postbuild()` in
`build.sh`, after `run_build()` finishes), and packaging into the AK3 zip
happens in `release/anykernel.sh`. This is a different shape from every
other addon here (all of which patch source/defconfig pre-build) — don't
move the clone logic into a patch step by mistake.

**EXPERIMENTAL**: hooks VFS and syscall hot paths (openat/statx/
newfstatat/faccessat/getxattr/readdir/etc). Upstream's own README says
"use in controlled environments only" — default is off (`build.yml`),
and the resulting `.ko` is shipped for manual insmod/ksud insmod, not
auto-loaded.

**No `KALLSYMS_ALL` injection needed** — Kasumi resolves non-exported
kernel symbols (`kallsyms_lookup_name` and friends) at runtime — needs
the full kallsyms table, not just exported ones
(`CONFIG_KALLSYMS_ALL`). Unlike BBRv3's `TCP_CONG_ADVANCED` gate,
`KALLSYMS_ALL` (depends on `DEBUG_KERNEL && KALLSYMS`) is already the
resolved default in stock `gki_defconfig` (`EXPERT` selects
`DEBUG_KERNEL`, and nothing in this repo ever disables
`EXPERT`/`DEBUG_KERNEL`), and `kernel/config/luminaire.fragment` sets it
explicitly on every build regardless — verified against real Kconfig
source + a built `conf` tool, not assumed. A prior version of this
script duplicated that injection early into `gki_defconfig` on the
(incorrect) assumption it needed BBRv3-style early placement — don't
re-add it without re-checking the dependency chain first.

**`KASUMI_SRC_DIR` export** — consumed later by
`kernel/addons/kasumi/postbuild.sh` (`run_postbuild()` in `build.sh`,
after `run_build()` finishes) and `release/anykernel.sh` (packaging).
Exported so it survives into those later stages. No separate "enabled"
flag needed — `run_postbuild()` gates on membership in
`$APPLIED_ADDONS`, same as this script only running when Kasumi passed
the kernel-version check in `run_addons()`.

---

## `kernel/addons/kasumi/postbuild.sh`

**Purpose of this file**: compiles `kasumi_lkm.ko` as an out-of-tree
module against the kernel tree `run_build()` just finished producing
(needs its `Module.symvers`).
