#!/usr/bin/env bash

# ======================================================
# 🏷️ BRANDING — CONFIG + APPLY
# ======================================================

export KERNEL_NAME="Luminaire"
export BUILD_USER="chainonyourdoor"
export BUILD_HOST="LuminaireCI"

export KBUILD_BUILD_USER="$BUILD_USER"
export KBUILD_BUILD_HOST="$BUILD_HOST"
export LOCALVERSION="-${ANDROID_VERSION}-${KMI_GENERATION}-${KERNEL_NAME}"
export KBUILD_BUILD_TIMESTAMP="$(date '+%a %b %d %T %Z %Y')"

# env vars are enough, kernel reads them directly
log "Branding: ${BUILD_USER}@${BUILD_HOST} | ${LOCALVERSION} ✅"
