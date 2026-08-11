#!/usr/bin/env bash

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

run_quiet() {
    local logfile rc
    logfile="$(mktemp)"
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

mark_stage_ok() {
    local marker="$1"
    [ -n "${GITHUB_ENV:-}" ] && echo "${marker}=true" >> "$GITHUB_ENV"
}

write_dry_run_image() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    echo "Luminaire Protocol — dry-run placeholder, not a real kernel image" > "$path"
    log "🧪 DRY RUN — wrote placeholder image to ${path} (compile skipped)"
}

resolve_android_version() {
    case "${KERNEL_VERSION}" in
        "5.10") echo "android12" ;;
        "5.15") echo "android13" ;;
        "6.1")  echo "android14" ;;
        "6.6")  echo "android15" ;;
        "6.6-konoha") echo "android15" ;;
        "6.12") echo "android16" ;;
        *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
    esac
}

run_setup() {
    echo "::group::📦 Setup"
    for script in "${LUMINAIRE_PATCH_DIR}/setup/"*.sh; do
        source "$script" || error "Setup failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

run_step() {
    local emoji="$1" label="$2" script="$3" missing_msg="$4"
    [ -f "$script" ] || error "$missing_msg"
    echo "::group::${emoji} ${label}"
    source "$script" || error "${label} script failed: $(basename "$script")"
    echo "::endgroup::"
}

wait_for_apt() {
    if [ -n "${APT_PID:-}" ]; then
        log "Waiting for background apt install (PID ${APT_PID})..."
        local waited=0 max_wait=600
        while kill -0 "$APT_PID" 2>/dev/null; do
            sleep 5
            waited=$((waited + 5))
            if [ "$waited" -ge "$max_wait" ]; then
                sudo kill -9 "$APT_PID" 2>/dev/null || true
                warn "apt install log tail (${APT_LOG:-/tmp/luminaire-apt-install.log}):"
                tail -n 50 "${APT_LOG:-/tmp/luminaire-apt-install.log}" 2>/dev/null || true
                error "Background apt install timed out after ${max_wait}s — killed PID ${APT_PID}"
            fi
        done
        if wait "$APT_PID"; then
            mkdir -p ~/.apt-cache
            sudo cp /var/cache/apt/archives/*.deb ~/.apt-cache/ 2>/dev/null || true
            log "Dependencies installed ✅"
        else
            warn "apt install log tail (${APT_LOG:-/tmp/luminaire-apt-install.log}):"
            tail -n 50 "${APT_LOG:-/tmp/luminaire-apt-install.log}" 2>/dev/null || true
            error "Background apt install failed!"
        fi
    fi
}

retry() {
    local max_attempts="$1"; shift
    local attempt=1 delay=5 rc=0
    while true; do
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

cache_freshness_note() {
    if [ "${CACHE_REFRESHED:-false}" = "true" ]; then
        echo "pre-warmed fresh by Prepare Arsenal this run"
    else
        echo "existing cache, no refresh requested — set 'Update Arsenal' to force"
    fi
}

verify_pinned_ref() {
    local label="$1" dir="$2" expected="$3" actual
    [[ "$expected" =~ ^[0-9a-f]{7,40}$ ]] || return 0
    actual="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")"
    if [ -z "$actual" ] || [[ "$actual" != "$expected"* ]]; then
        error "${label}: pinned ref ${expected} did not check out (HEAD is ${actual:-unknown}) — pin is likely stale/unreachable upstream, needs re-pin in the manifest"
    fi
    log "${label}: pin verified at ${actual:0:12} ✅"
}

mode_emoji() {
    case "$1" in
        "Dry Run")  echo "🧪" ;;
        "Warm Run") echo "🔥" ;;
        "Build")    echo "🔬" ;;
        "Release") echo "🚀" ;;
        *)         echo "❓" ;;
    esac
}
