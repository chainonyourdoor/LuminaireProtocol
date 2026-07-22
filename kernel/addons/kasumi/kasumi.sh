#!/usr/bin/env bash

# ======================================================
# 🥷 ADDON — Kasumi (path manipulation/hiding LKM)
# by Anatdx
# Repo: https://github.com/Anatdx/Kasumi
# ======================================================

KASUMI_REPO="https://github.com/Anatdx/Kasumi.git"
KASUMI_SRC_DIR="${WORKSPACE_DIR}/kasumi"

log "🥷 Fetching Kasumi source..."

if [ -d "${KASUMI_SRC_DIR}/.git" ]; then
    log "Kasumi: source already present, skipping clone."
else
    rm -rf "${KASUMI_SRC_DIR}"
    retry 3 run_quiet git clone -q --depth=1 "${KASUMI_REPO}" "${KASUMI_SRC_DIR}" \
        || error "Kasumi: failed to clone source!"
fi

[ -d "${KASUMI_SRC_DIR}/src" ] || error "Kasumi: cloned repo missing src/ — layout may have changed upstream!"

export KASUMI_SRC_DIR

log "Kasumi source ready at ${KASUMI_SRC_DIR} ✅ (module build deferred to post-build stage)"
