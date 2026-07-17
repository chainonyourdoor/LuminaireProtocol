#!/usr/bin/env bash

# ==================
# 🔧 FUNCTIONS
# ==================

COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

log() {
  echo -e "${COLOR_CYAN}[LOG]${COLOR_RESET} $*" >&2
}

warn() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

error() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
  exit 1
}

# Runs a command, capturing combined stdout+stderr to a temp file.
# Silent on success. On failure, prints the last 50 lines so the
# real underlying error is visible instead of a blank failure.
run_quiet() {
    local logfile rc
    logfile="$(mktemp)"
    # Capture the exit status on its own line right after the command,
    # not via `$?` after an `if cmd; then ...; fi` with no else — bash
    # resets $? to 0 for that construct when the condition is false,
    # which silently turned every command failure into a false success.
    "$@" > "$logfile" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        rm -f "$logfile"
        return 0
    fi
    echo -e "${COLOR_YELLOW}---- command output (last 50 lines) ----${COLOR_RESET}"
    tail -n 50 "$logfile"
    echo -e "${COLOR_YELLOW}-----------------------------------------${COLOR_RESET}"
    rm -f "$logfile"
    return "$rc"
}

# Exports a "this stage actually finished" marker to $GITHUB_ENV. Called
# right after a build.sh stage completes (see main()). Thanks to `set -e`,
# a failing stage exits before its own mark_stage_ok call ever runs — so
# checkpoint/engine.sh can tell *which* stage a failure happened in just by
# checking which of these markers made it into the job's env. This is what
# lets engine.sh avoid blaming a KSU-fork/SuSFS candidate for a failure that
# actually happened in an unrelated later stage (e.g. an addon like ADIOS
# failing to apply) instead of in run_variant/run_build where that candidate
# is actually exercised. No-op outside CI (GITHUB_ENV unset) so this is safe
# to call from a local/manual run of build.sh too.
mark_stage_ok() {
    local marker="$1"
    [ -n "${GITHUB_ENV:-}" ] && echo "${marker}=true" >> "$GITHUB_ENV"
}

# Writes a placeholder file at the path a real kernel Image would occupy,
# so release/anykernel.sh's packaging step (and everything downstream of
# it — Telegram notify, checkpoint promotion) can be exercised without
# actually compiling. Used by build/make.sh when
# DRY_RUN=true, which build.yml only ever sets when RUN_MODE="Dry Run".
write_dry_run_image() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    echo "Luminaire Protocol — dry-run placeholder, not a real kernel image" > "$path"
    log "🧪 DRY RUN — wrote placeholder image to ${path} (compile skipped)"
}

# Maps KERNEL_VERSION (e.g. "6.1") to its ANDROID_VERSION branch prefix
# (e.g. "android14"). Shared by build.sh and arsenal.sh so the version
# table only needs updating in one place when a new kernel is added.
resolve_android_version() {
    case "${KERNEL_VERSION}" in
        "5.10") echo "android12" ;;
        "5.15") echo "android13" ;;
        "6.1")  echo "android14" ;;
        "6.6")  echo "android15" ;;
        "6.12") echo "android16" ;;
        *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
    esac
}

# Sources every *.sh in setup/, in order. Shared by build.sh and arsenal.sh.
run_setup() {
    echo "::group::📦 Setup"
    for script in "${LUMINAIRE_PATCH_DIR}/setup/"*.sh; do
        source "$script" || error "Setup failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# Waits for the background apt install kicked off by setup/01_deps.sh
# (APT_PID). Shared by build.sh and arsenal.sh so a fresh runner never
# proceeds into ccache/build steps before required packages land.
wait_for_apt() {
    if [ -n "${APT_PID:-}" ]; then
        log "Waiting for background apt install (PID ${APT_PID})..."
        if wait "$APT_PID"; then
            mkdir -p ~/.apt-cache
            sudo cp /var/cache/apt/archives/*.deb ~/.apt-cache/ 2>/dev/null || true
            log "Dependencies installed ✅"
        else
            error "Background apt install failed!"
        fi
    fi
}

# Retries a command with exponential backoff.
# Usage: retry <max_attempts> <command...>
retry() {
    local max_attempts="$1"; shift
    local attempt=1 delay=5 rc=0
    while true; do
        # Same fix as run_quiet(): capture $? on its own line right after
        # the command, not via `if cmd; then ...; fi` with no else — bash
        # resets $? to 0 for that construct when the condition is false.
        "$@"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            return 0
        fi
        if [ "$attempt" -ge "$max_attempts" ]; then
            return "$rc"
        fi
        warn "Attempt ${attempt}/${max_attempts} failed — retrying in ${delay}s..."
        sleep "$delay"
        delay=$(( delay * 2 ))
        attempt=$(( attempt + 1 ))
    done
}

# Human-readable note on WHY a cache-restore path is being taken, for
# clang/kernel-source/AK3 restore log lines. Start-Build always restores
# (USE_*_CACHE hardcoded "true" there) — Prepare Arsenal is the single
# choke point that decides whether that shared cache is actually fresh
# this run (CACHE_REFRESHED, set from the 'Update Arsenal' input). Without
# this, "restored from cache ✅" reads the same whether the cache is
# brand new or weeks old, which is misleading when read from a single
# job's log in isolation.
cache_freshness_note() {
    if [ "${CACHE_REFRESHED:-false}" = "true" ]; then
        echo "pre-warmed fresh by Prepare Arsenal this run"
    else
        echo "existing cache, no refresh requested — set 'Update Arsenal' to force"
    fi
}

# Emoji for a given RUN_MODE, used in build.sh's opening/closing banners.
# Kept as a lookup instead of embedding the emoji into RUN_MODE itself,
# since RUN_MODE is exact-string-compared elsewhere (scout.sh, telegram.sh,
# and build.sh's own "${RUN_MODE^^}" = "WARM RUN" check) — mutating its
# value here would silently break those.
mode_emoji() {
    case "$1" in
        "Dry Run")  echo "🧪" ;;
        "Warm Run") echo "🔥" ;;
        "Build")    echo "🔬" ;;
        "Release") echo "🚀" ;;
        *)         echo "❓" ;;
    esac
}
