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
