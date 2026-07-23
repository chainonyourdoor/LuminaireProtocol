#!/usr/bin/env bash

SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')" || true
[ -n "$SUBLEVEL" ] || error "SUBLEVEL not found in kernel Makefile — kernel source may be missing or corrupted!"
KMI_GENERATION="$(grep '^KMI_GENERATION=' \
    "${KERNEL_SRC}/build.config.common" \
    "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)" || true
[ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found!"
export SUBLEVEL KMI_GENERATION
echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

export KERNEL_NAME="Luminaire"
export BUILD_USER="chainonyourdoor"
export BUILD_HOST="LuminaireCI"

export KBUILD_BUILD_USER="$BUILD_USER"
export KBUILD_BUILD_HOST="$BUILD_HOST"
export LOCALVERSION="-${ANDROID_VERSION}-${KMI_GENERATION}-${KERNEL_NAME}"
export KBUILD_BUILD_TIMESTAMP="$(date '+%a %b %d %T %Z %Y')"

log "Branding: ${BUILD_USER}@${BUILD_HOST} | ${LOCALVERSION} ✅"
