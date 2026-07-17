#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Arsenal Orchestrator
# ======================================================

set -eo pipefail

# GitHub Actions captures stdout and stderr as separate buffered streams and
# doesn't guarantee their relative order in the rendered log. log()/warn()/
# error() write to stderr while ::group::/::endgroup:: (below) write to
# stdout, so without this, log lines can render outside the ::group:: block
# they were actually written inside of. Merging stderr into stdout here
# keeps everything on one stream, preserving actual write order.
exec 2>&1

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

ANDROID_VERSION="$(resolve_android_version)"
KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LUMINAIRE_PATCH_DIR="${ROOT_DIR}"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo "========================================"
    echo "  ✨ Luminaire Arsenal ✨"
    echo "========================================"
    echo "  🏷️ ${ANDROID_VERSION}-${KERNEL_VERSION}"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "  📅 $(date)"
    echo "========================================"

    run_setup
    mkdir -p "$KERNEL_DIR" "$OUT_DIR"
    run_download

    # Called here (not right after run_setup) so the background apt install
    # kicked off by setup/01_deps.sh overlaps with run_download's network-
    # bound kernel source fetch instead of blocking in front of it. Grouped
    # together with the final "ready" log since both are just wrap-up, not
    # part of the download itself.
    echo "::group::🏁 Finalize"
    wait_for_apt
    echo "::endgroup::"

    echo "========================================"
    echo "  ✅ Arsenal Ready! ✅"
    echo "  🏷️ ${ANDROID_VERSION}-${KERNEL_VERSION}"
    echo "========================================"
}


# ======================================================
# 📥 DOWNLOAD
# ======================================================
# (run_setup() is defined in functions.sh, shared with build.sh)

run_download() {
    echo "::group::📥 Arsenal Download"
    source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    log "Arsenal downloaded ✅"
    echo "::endgroup::"
}

main "$@"
