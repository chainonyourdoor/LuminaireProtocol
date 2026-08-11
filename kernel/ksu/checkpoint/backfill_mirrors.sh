#!/usr/bin/env bash
set -eo pipefail

LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:-$GITHUB_WORKSPACE}"
source "${LUMINAIRE_PATCH_DIR}/functions.sh"
source "${LUMINAIRE_PATCH_DIR}/kernel/ksu/checkpoint/mirrors.sh"

for manifest in "${LUMINAIRE_PATCH_DIR}"/kernel/ksu/manifests/*.json; do
    version_label="$(basename "$manifest" .json)"
    for key in "${!MIRROR_SOURCE_URL[@]}"; do
        ref="$(jq -r ".${key}.good // \"\"" "$manifest")"
        [ -n "$ref" ] || continue
        log "backfill: ${version_label}/${key} -> ${ref:0:12}"
        mirror_promote "$key" "$ref" "$version_label"
    done
done
