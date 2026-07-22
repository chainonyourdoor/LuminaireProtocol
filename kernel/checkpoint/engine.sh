#!/usr/bin/env bash
# ======================================================
# 🛡️ Engine — checkpoint save/hold (promote or blacklist)
# ======================================================
# Runs after the build step (always, even on failure).
#
# - Candidate succeeded  -> promote it: manifest's "good" becomes this SHA.
# - Candidate failed     -> blacklist it: append to "bad", "good" untouched
#                           (this IS the rollback — nothing else changes).
# - No candidate was used this run -> nothing to do.
#
# Matrix jobs (RESUKISU / SUKISU) run in parallel and may both try to
# write manifest.json at the same time, so every write goes through a
# fetch-rebase-push retry loop instead of a single commit+push.
#
# Args: <build outcome: "success" | "failure"> <space-separated component keys to check, e.g. "resukisu susfs">

set -eo pipefail

LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:-$GITHUB_WORKSPACE}"
source "${LUMINAIRE_PATCH_DIR}/functions.sh"
cd "$LUMINAIRE_PATCH_DIR"

BUILD_OUTCOME="$1"
shift
COMPONENTS=("$@")

[ -n "${KERNEL_VERSION:-}" ] || error "checkpoint: KERNEL_VERSION not set"
MANIFEST_REL="kernel/$(resolve_android_version)-${KERNEL_VERSION}/manifest.json"
MANIFEST="${LUMINAIRE_PATCH_DIR}/${MANIFEST_REL}"

any_candidate_used="false"
for key in "${COMPONENTS[@]}"; do
    prefix="${key^^}"
    candidate_var="CANDIDATE_${prefix}"
    [ "${!candidate_var:-false}" = "true" ] && any_candidate_used="true"
done

if [ "$any_candidate_used" = "false" ]; then
    log "checkpoint: no candidate ref used this run — nothing to update"
    exit 0
fi

[ -n "${PERSONAL_TOKEN:-}" ] || error "checkpoint: PERSONAL_TOKEN not set — cannot push manifest update"

git config --global user.name  "luminaire-bot"
git config --global user.email "luminaire-bot@users.noreply.github.com"

# The github-actions[bot]/403 push failure is fixed in build.yml's
# Start-Build checkout step (persist-credentials: false), not here.
# actions/checkout v6+ persists its injected auth header via a global
# `includeIf.gitdir` config pointing at a file under $RUNNER_TEMP, rather
# than this repo's local .git/config — so an unset targeting
# http.https://github.com/.extraheader here has no effect; the fix has
# to happen at the checkout step itself. See actions/checkout's v6
# changelog/issue tracker (PR "Persist creds to a separate file").
REMOTE="https://x-access-token:${PERSONAL_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Applies one jq patch to manifest.json on top of the latest main and
# pushes, retrying on a fast-forward conflict from a concurrent matrix job.
apply_and_push() {
    local jq_patch="$1" commit_msg="$2"
    local attempt=1 max_attempts=5

    while [ "$attempt" -le "$max_attempts" ]; do
        run_quiet git fetch "$REMOTE" main
        # Must actually move local HEAD to FETCH_HEAD before committing —
        # git fetch alone doesn't. Without this, every retry re-commits on
        # top of the same stale parent, so a real conflict (a concurrent
        # matrix job's push) fails identically on every attempt and this
        # loop can never actually recover (confirmed with a real two-clone
        # repro before landing this fix: 0/5 attempts succeeded without
        # this line, 1/1 with it). workspace/ is gitignored, so this
        # doesn't touch the in-progress kernel source tree.
        git reset -q --hard FETCH_HEAD

        # First-ever checkpoint write for this kernel version: the file
        # (and its folder) won't exist in the repo yet. That's normal, not
        # an error — bootstrap an empty object so jq has something to patch.
        mkdir -p "$(dirname "$MANIFEST")"
        [ -f "$MANIFEST" ] || echo '{}' > "$MANIFEST"

        # A failing jq here used to be silently swallowed: mv never ran, so
        # manifest.json stayed unchanged, git found "nothing to commit", and
        # apply_and_push returned 0 as if the update had actually happened —
        # confirmed for real on the promote path (.bad -= [...] errors when
        # .bad is null/missing, which every fresh-reset manifest.json hits).
        # Fail loud instead so a broken jq_patch is never mistaken for a
        # legitimate no-op.
        jq "$jq_patch" "$MANIFEST" > "${MANIFEST}.tmp" \
            || error "checkpoint: jq patch failed against ${MANIFEST_REL} — patch: ${jq_patch}"
        mv "${MANIFEST}.tmp" "$MANIFEST"

        (
            git add "$MANIFEST_REL"
            git commit -q -m "$commit_msg" 2>/dev/null || { echo "nothing to commit"; exit 0; }
            git push "$REMOTE" "HEAD:main"
        ) && return 0

        warn "checkpoint: push conflict (attempt ${attempt}/${max_attempts}) — retrying..."
        attempt=$(( attempt + 1 ))
        sleep $(( RANDOM % 5 + 2 ))
    done

    error "checkpoint: failed to push manifest update after ${max_attempts} attempts"
}

# Opens (or leaves open) a GitHub Issue for a broken upstream component,
# de-duplicated by a stable title so repeated failed re-tests don't spam.
file_issue() {
    local key="$1" ref="$2"
    local title="🔴 Upstream build failure: ${key} (${KERNEL_VERSION})"
    local existing
    existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"${title}\"" --json number --jq '.[0].number' 2>/dev/null || true)

    local body="Latest upstream commit \`${ref}\` for **${key}** failed to build (run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}).

Still pinned to the last known-good commit — no action needed unless you want to investigate upstream. This issue will auto-close once a build succeeds again for ${key}."

    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body" || warn "file_issue: couldn't comment on existing issue #${existing}"
    else
        # gh issue create fails outright (no issue at all) if the label
        # doesn't already exist in the repo — create it first, idempotently.
        gh label create "upstream-broken" --repo "$GITHUB_REPOSITORY" \
            --color "d73a4a" --description "Auto-filed: an upstream pin candidate failed to build" \
            2>/dev/null || true
        gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body "$body" --label "upstream-broken" || warn "file_issue: couldn't create issue for ${key}"
    fi
}

close_issue_if_open() {
    local key="$1"
    local title="🔴 Upstream build failure: ${key} (${KERNEL_VERSION})"
    local existing
    existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"${title}\"" --json number --jq '.[0].number' 2>/dev/null || true)
    [ -n "$existing" ] && [ "$existing" != "null" ] && \
        gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --comment "✅ Build succeeded again — pin promoted to a new known-good commit." 2>/dev/null || true
}

for key in "${COMPONENTS[@]}"; do
    prefix="${key^^}"
    candidate_var="CANDIDATE_${prefix}"
    [ "${!candidate_var:-false}" = "true" ] || continue

    ref_var="${prefix}_REF"
    ref="${!ref_var}"

    if [ "$BUILD_OUTCOME" = "success" ]; then
        log "checkpoint: promoting ${key} pin to ${ref:0:12} (kernel ${KERNEL_VERSION})"
        apply_and_push ".${key}.good = \"${ref}\" | .${key}.bad = ((.${key}.bad // []) - [\"${ref}\"])" "chore: bump ${key} pin to ${ref:0:12} for kernel ${KERNEL_VERSION} (verified via run ${GITHUB_RUN_ID})"
        close_issue_if_open "$key"
        continue
    fi

    # Failure. build.sh's main() only sets these markers via mark_stage_ok()
    # once the corresponding stage actually finishes (see functions.sh) —
    # `set -e` means a stage that fails never reaches its own marker, so
    # their presence tells us which stage the failure was in without
    # engine.sh needing any of build.sh's internal state.
    #
    # - CHECKPOINT_VARIANT_OK missing -> failed at/before run_variant,
    #   which is exactly where this candidate ref gets applied -> blame it.
    # - CHECKPOINT_VARIANT_OK present but CHECKPOINT_ADDONS_OK missing ->
    #   failed in run_core or run_addons, both unrelated to the KSU-fork/
    #   SuSFS candidate this component tracks -> leave the pin alone.
    # - CHECKPOINT_ADDONS_OK present but CHECKPOINT_BUILD_OK missing ->
    #   failed in run_build itself (the actual compile), which the
    #   candidate patch can absolutely still be the cause of -> blame it,
    #   same as a run_variant-stage failure.
    # - CHECKPOINT_BUILD_OK present -> run_build already finished, so the
    #   failure happened in run_postbuild (e.g. Kasumi's out-of-tree LKM
    #   compile) — unrelated to the KSU-fork/SuSFS candidate, which is only
    #   ever exercised in run_variant/run_build -> leave the pin alone. This
    #   used to be conflated with the run_build case above (no marker
    #   existed between the two), which wrongly blacklisted susfs_resukisu/
    #   susfs_sukisu candidate be08face56c3 for kernel 5.10 over an
    #   unrelated Kasumi post-build failure — see manifest.json history.
    if [ "${CHECKPOINT_VARIANT_OK:-false}" = "true" ] && [ "${CHECKPOINT_ADDONS_OK:-false}" != "true" ]; then
        log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed in an unrelated stage (run_core/run_addons), not in run_variant/run_build (kernel ${KERNEL_VERSION})"
        continue
    fi

    if [ "${CHECKPOINT_ADDONS_OK:-false}" = "true" ] && [ "${CHECKPOINT_BUILD_OK:-false}" = "true" ]; then
        log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed in an unrelated stage (run_postbuild), not in run_variant/run_build (kernel ${KERNEL_VERSION})"
        continue
    fi

    warn "checkpoint: blacklisting ${key} candidate ${ref:0:12} (build failed, kernel ${KERNEL_VERSION})"
    apply_and_push ".${key}.bad |= (. + [\"${ref}\"] | unique)" "chore: mark ${key} candidate ${ref:0:12} as known-bad for kernel ${KERNEL_VERSION} (run ${GITHUB_RUN_ID})"
    file_issue "$key" "$ref"
done
