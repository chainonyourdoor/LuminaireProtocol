#!/usr/bin/env bash

set -eo pipefail

exec 2>&1

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

ANDROID_VERSION="$(resolve_android_version)"
KERNEL_BRANCH="${KERNEL_BRANCH_OVERRIDE:-${ANDROID_VERSION}-${KERNEL_VERSION}-live}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LUMINAIRE_PATCH_DIR="${ROOT_DIR}"

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

    echo "::group::🏁 Finalize"
    wait_for_apt
    echo "::endgroup::"

    echo "========================================"
    echo "  ✅ Arsenal Ready! ✅"
    echo "  🏷️ ${ANDROID_VERSION}-${KERNEL_VERSION}"
    echo "========================================"
}


run_download() {
    echo "::group::📥 Arsenal Download"
    source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    log "Arsenal downloaded ✅"
    echo "::endgroup::"
}

main "$@"
