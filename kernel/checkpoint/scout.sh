#!/usr/bin/env bash
# ======================================================
# 🔭 Scout — checkpoint reconnaissance (pin vs candidate)
# ======================================================
# Decides which git ref (commit SHA) each tracked upstream component
# (ReSukiSU, SukiSU-Ultra, SuSFS) should build against for this run.
#
# - RUN_MODE=Release: always use the manifest's known-good pin. Never
#   queries upstream, never builds an untested candidate.
# - RUN_MODE=Build/Warm Run: queries upstream's latest commit. If it
#   differs from the pin and isn't already known-bad, that becomes the
#   candidate for this run — and checkpoint/engine.sh decides after
#   the build whether to promote it or blacklist it.
# - Exception (deadlock-breaking retest): if no good pin exists yet AND
#   the latest upstream commit is already blacklisted, there is no known-
#   good ref to fall back to at all. Falling back to an empty ref there
#   would just make build scripts silently default to cloning upstream's
#   branch HEAD anyway (the very commit that's blacklisted) without ever
#   tracking it as a candidate — a permanent deadlock where Release mode
#   can never pass no matter how many Warm Run/Build runs succeed. In that
#   specific case only, the blacklisted ref is retried as a last-resort
#   candidate so a real build outcome can promote or re-blacklist it.
#
# Exports (via $GITHUB_ENV) for each relevant component:
#   <COMPONENT>_REF        — the SHA to actually build against
#   CANDIDATE_<COMPONENT>  — "true" if REF is an unverified candidate

set -eo pipefail

LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:-$GITHUB_WORKSPACE}"
source "${LUMINAIRE_PATCH_DIR}/functions.sh"

[ -n "${KERNEL_VERSION:-}" ] || error "scout: KERNEL_VERSION not set"
MANIFEST="${LUMINAIRE_PATCH_DIR}/kernel/$(resolve_android_version)-${KERNEL_VERSION}-lts/manifest.json"

# A kernel version with no manifest.json yet just means no pin has ever
# been promoted for it — normal for a kernel version without checkpoint
# history yet, not a misconfiguration. Fall back to an empty object so
# resolve_component's // "" / // [] defaults kick in the same way they
# would for a fork key missing from an existing manifest.
if [ ! -f "$MANIFEST" ]; then
    warn "scout: no manifest yet for kernel ${KERNEL_VERSION} — treating as no pins/candidates yet"
    MANIFEST="$(mktemp)"
    echo '{}' > "$MANIFEST"
fi

GH_API_AUTH=()
[ -n "${PERSONAL_TOKEN:-}" ] && GH_API_AUTH=(-H "Authorization: Bearer ${PERSONAL_TOKEN}")

# Fetches the latest commit SHA for a component. Never fails the build —
# a lookup problem just means "no candidate this run, use the pin".
# Args: <component name for logging> <curl command to run> <jq filter>
latest_sha_or_empty() {
    local label="$1" url="$2" jq_filter="$3"
    local body_file http_code curl_exit sha auth_args=()

    # GH_API_AUTH is a GitHub PAT — only attach it for api.github.com calls.
    # Sending it to a non-GitHub target like gitlab.com (e.g. the SuSFS
    # lookup) is a foreign/invalid Authorization header from GitLab's point
    # of view, which it rejects quickly (~300ms, consistent every run —
    # not the profile of a timeout or rate-limit). Scoping the header to
    # its actual target avoids this; the http_code/curl_exit logging below
    # gives concrete evidence if a lookup ever fails again.
    case "$url" in
        https://api.github.com/*) auth_args=("${GH_API_AUTH[@]}") ;;
    esac

    body_file="$(mktemp)"
    if http_code=$(curl -sL -o "$body_file" -w '%{http_code}' --max-time 20 \
            "${auth_args[@]}" "$url"); then
        curl_exit=0
    else
        curl_exit=$?
    fi

    if [ "$curl_exit" -ne 0 ] || [ "$http_code" != "200" ]; then
        warn "scout: couldn't reach upstream for ${label} (curl exit ${curl_exit}, HTTP ${http_code:-000}) — using pinned ref"
        rm -f "$body_file"
        echo ""
        return 0
    fi

    sha=$(jq -r "$jq_filter" "$body_file" 2>/dev/null)
    rm -f "$body_file"
    if [ -z "$sha" ] || [ "$sha" = "null" ]; then
        warn "scout: couldn't parse latest ${label} commit — using pinned ref"
        echo ""
        return 0
    fi
    echo "$sha"
}

# Resolves one component: compares latest upstream against pin + bad-list,
# exports <COMPONENT>_REF / CANDIDATE_<COMPONENT> to $GITHUB_ENV.
# Args: <component key in manifest> <env var prefix> <latest-sha (may be empty)>
resolve_component() {
    local key="$1" prefix="$2" latest="$3"
    local good bad_list is_bad ref candidate

    good=$(jq -r ".${key}.good // \"\"" "$MANIFEST")
    bad_list=$(jq -c ".${key}.bad // []" "$MANIFEST")

    if [ "${RUN_MODE^^}" = "RELEASE" ]; then
        [ -n "$good" ] || error "scout: RUN_MODE=Release but no known-good ${key} pin exists yet — run a Build first."
        ref="$good"; candidate="false"
        log "${prefix}: Release mode — pinned to ${ref:0:12} (no upstream check)"
    elif [ -z "$latest" ]; then
        ref="$good"; candidate="false"
        log "${prefix}: no candidate available — using pinned ${good:0:12}"
    elif [ "$latest" = "$good" ]; then
        ref="$good"; candidate="false"
        log "${prefix}: up to date at ${good:0:12}"
    else
        is_bad=$(echo "$bad_list" | jq --arg sha "$latest" 'any(. == $sha)')
        if [ "$is_bad" = "true" ]; then
            if [ -n "$good" ]; then
                ref="$good"; candidate="false"
                warn "${prefix}: latest upstream ${latest:0:12} is known-bad — falling back to pinned ${good:0:12}"
            else
                # Deadlock case: no good pin exists yet AND the only ref
                # upstream has ever offered is already blacklisted. Without
                # this branch, ref falls back to the empty "$good" forever —
                # downstream build scripts then silently default to cloning
                # upstream's branch HEAD anyway (i.e. this exact "bad" SHA),
                # but since candidate stays "false" here, engine.sh never
                # gets a chance to promote it even when that build succeeds.
                # Net effect: Release mode can never pass for this component,
                # no matter how many green Warm Run/Build runs happen against
                # it — confirmed on SUKISU+SUSFS (sukisu_builtin stuck on
                # b88403d2561b since it was blacklisted in run 28687541974;
                # upstream's builtin branch hasn't moved since).
                # Retry it as a last-resort candidate instead: a success
                # promotes it and breaks the deadlock; a failure just
                # re-blacklists the same SHA (engine.sh's `bad |= (. + [...])
                # | unique` makes that a no-op), so this can't make things
                # worse than the permanent-failure state it replaces.
                ref="$latest"; candidate="true"
                warn "${prefix}: latest upstream ${latest:0:12} is known-bad and no good pin exists — retrying it as a last-resort candidate to break the deadlock"
            fi
        else
            ref="$latest"; candidate="true"
            log "${prefix}: new candidate ${latest:0:12} (pinned: ${good:-none}) — will verify this build"
        fi
    fi

    echo "${prefix}_REF=${ref}"       >> "$GITHUB_ENV"
    echo "CANDIDATE_${prefix}=${candidate}" >> "$GITHUB_ENV"
}

case "$KERNEL_VARIANT" in
    RESUKISU)
        latest=$(latest_sha_or_empty "ReSukiSU" \
            "https://api.github.com/repos/ReSukiSU/ReSukiSU/commits/main" '.sha')
        resolve_component "resukisu" "RESUKISU" "$latest"

        if [ "$SUSFS_ENABLED" = "true" ]; then
            latest=$(latest_sha_or_empty "SuSFS (ReSukiSU pairing)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/gki-android14-6.1" '.id')
            resolve_component "susfs_resukisu" "SUSFS_RESUKISU" "$latest"
        fi
        ;;
    SUKISU)
        if [ "$SUSFS_ENABLED" = "true" ]; then
            # The "builtin" branch is SukiSU-Ultra's own SUSFS-integrated
            # line — actively maintained by the SukiSU-Ultra team to stay
            # in sync with SuSFS, unlike "main" which moved to an
            # architecture (syscall_hook_manager) that isn't compatible
            # with SuSFS's adapter patches at all. So for the SUSFS case we
            # track this branch's tip directly instead of a hand-curated
            # pin pair — same simple model as ReSukiSU's tracking.
            latest=$(latest_sha_or_empty "SukiSU-Ultra (builtin)" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/commits/builtin" '.sha')
            resolve_component "sukisu_builtin" "SUKISU_BUILTIN" "$latest"

            latest=$(latest_sha_or_empty "SuSFS (SukiSU pairing)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/gki-android14-6.1" '.id')
            resolve_component "susfs_sukisu" "SUSFS_SUKISU" "$latest"
        else
            # SukiSU-Ultra's own setup.sh defaults to the latest *tag* (not
            # main HEAD) when no ref is given — match that semantic here.
            tag=$(latest_sha_or_empty "SukiSU-Ultra release" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/releases/latest" '.tag_name')
            latest=""
            [ -n "$tag" ] && latest=$(latest_sha_or_empty "SukiSU-Ultra" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/commits/${tag}" '.sha')
            resolve_component "sukisu" "SUKISU" "$latest"
        fi
        ;;
    KSUNEXT)
        if [ "$SUSFS_ENABLED" = "true" ]; then
            # Official KernelSU-Next's dev branch dropped the manual hook
            # API SuSFS's kernel patch depends on (moved to
            # syscall_hook_manager) — confirmed by a real build (undefined
            # ksu_handle_*/susfs_* symbols at link time, run 28714488530).
            # pershoot maintains a KernelSU-Next fork with a dev-susfs
            # branch that keeps SUSFS-compatible hooks, paired with their
            # own susfs4ksu fork/branch below. Maintainer flags this fork
            # as not production-ready — tracked like any other candidate.
            latest=$(latest_sha_or_empty "KernelSU-Next (pershoot dev-susfs fork)" \
                "https://api.github.com/repos/pershoot/KernelSU-Next/commits/dev-susfs" '.sha')
            resolve_component "ksunext_susfs_fork" "KSUNEXT_SUSFS_FORK" "$latest"

            latest=$(latest_sha_or_empty "SuSFS (KSU-Next pairing, pershoot fork)" \
                "https://gitlab.com/api/v4/projects/pershoot%2Fsusfs4ksu/repository/commits/gki-android14-6.1-dev" '.id')
            resolve_component "susfs_ksunext" "SUSFS_KSUNEXT" "$latest"
        else
            # KernelSU-Next's own setup.sh defaults to the latest *tag* when
            # no ref is given (same semantic as SukiSU-Ultra's non-SUSFS
            # branch) — match that here.
            tag=$(latest_sha_or_empty "KernelSU-Next release" \
                "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/latest" '.tag_name')
            latest=""
            [ -n "$tag" ] && latest=$(latest_sha_or_empty "KernelSU-Next" \
                "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/commits/${tag}" '.sha')
            resolve_component "ksunext" "KSUNEXT" "$latest"
        fi
        ;;
    VANILLA)
        log "scout: VANILLA — nothing to track"
        ;;
esac
