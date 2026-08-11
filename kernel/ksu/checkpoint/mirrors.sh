#!/usr/bin/env bash

# ======================================================
# 🪞 Checkpoint Mirrors
# ======================================================
# See docs/CODEX.md for the full rationale.

declare -gA MIRROR_SOURCE_URL=(
    [resukisu]="https://github.com/ReSukiSU/ReSukiSU"
    [sukisu_builtin]="https://github.com/SukiSU-Ultra/SukiSU-Ultra"
    [ksunext_susfs_fork]="https://github.com/pershoot/KernelSU-Next"
    [susfs_resukisu]="https://gitlab.com/simonpunk/susfs4ksu.git"
    [susfs_sukisu]="https://gitlab.com/simonpunk/susfs4ksu.git"
    [susfs_ksunext]="https://gitlab.com/simonpunk/susfs4ksu.git"
)

declare -gA MIRROR_REPO=(
    [resukisu]="chainonyourdoor/ReSukiSU"
    [sukisu_builtin]="chainonyourdoor/SukiSU-Ultra"
    [ksunext_susfs_fork]="chainonyourdoor/KernelSU-Next"
    [susfs_resukisu]="chainonyourdoor/susfs4ksu-mirror"
    [susfs_sukisu]="chainonyourdoor/susfs4ksu-mirror"
    [susfs_ksunext]="chainonyourdoor/susfs4ksu-mirror"
)

mirror_clone_url() {
    local key="$1"
    [ -n "${MIRROR_REPO[$key]:-}" ] || return 1
    echo "https://github.com/${MIRROR_REPO[$key]}.git"
}

mirror_push_url() {
    local key="$1"
    [ -n "${MIRROR_REPO[$key]:-}" ] || return 1
    [ -n "${PERSONAL_TOKEN:-}" ] || return 1
    echo "https://x-access-token:${PERSONAL_TOKEN}@github.com/${MIRROR_REPO[$key]}.git"
}

mirror_branch() {
    echo "pin/$2/$1"
}

mirror_promote() {
    local key="$1" ref="$2" version_label="$3"
    local src="${MIRROR_SOURCE_URL[$key]:-}"
    local dst; dst="$(mirror_push_url "$key" 2>/dev/null)" || true
    [ -n "$src" ] && [ -n "$dst" ] || return 0

    log "mirror: copying ${key} commit ${ref:0:12} to $(mirror_branch "$key" "$version_label") on ${MIRROR_REPO[$key]}..."
    local tmp; tmp="$(mktemp -d)"
    local rc=0
    (
        cd "$tmp" || exit 1
        git init -q
        git remote add src "$src"
        git remote add dst "$dst"
        # Always a full (non-shallow) fetch, not shallow --depth=1. A shallow
        # fetch immediately pushed to a *different* remote/host routinely
        # fails with "did not receive expected object" / "index-pack
        # failed" — the destination can't reliably reconstruct a pack built
        # against a shallow boundary it doesn't share. Same conclusion
        # kernel-source.yml already reached for the same reason (see its
        # comments). These mirror source repos are small (seconds, low
        # single-digit MB), so there's no real cost to skipping shallow.
        run_quiet git fetch src "$ref" || exit 1
        git push -q dst "${ref}:refs/heads/$(mirror_branch "$key" "$version_label")" --force
    ) || rc=$?
    rm -rf "$tmp"
    [ "$rc" -eq 0 ] \
        && log "mirror: ${key} mirrored ✅" \
        || warn "mirror: ${key} — copy to mirror failed (non-fatal, manifest pin was still updated)"
}

mirror_preseed() {
    local key="$1" target_dir="$2" ref="$3" is_candidate="$4" version_label="$5"
    [ "$is_candidate" = "true" ] && return 1
    [ -n "$ref" ] || return 1
    [ -e "$target_dir" ] && return 1
    local url; url="$(mirror_clone_url "$key" 2>/dev/null)" || return 1

    log "mirror: pre-seeding ${key} from $(mirror_branch "$key" "$version_label") on ${MIRROR_REPO[$key]}..."
    if ! run_quiet git clone -q -b "$(mirror_branch "$key" "$version_label")" "$url" "$target_dir"; then
        warn "mirror: ${key} — mirror branch not found/reachable, falling back to upstream clone"
        rm -rf "$target_dir"
        return 1
    fi
    if ! (cd "$target_dir" && git checkout -q "$ref"); then
        warn "mirror: ${key} — ref ${ref:0:12} not found on mirror, falling back to upstream clone"
        rm -rf "$target_dir"
        return 1
    fi
    log "mirror: ${key} pre-seeded ✅"
    return 0
}
