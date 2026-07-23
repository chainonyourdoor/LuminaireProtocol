#!/usr/bin/env bash
set -eo pipefail

LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:-$GITHUB_WORKSPACE}"
source "${LUMINAIRE_PATCH_DIR}/functions.sh"

[ -n "${KERNEL_VERSION:-}" ] || error "scout: KERNEL_VERSION not set"
MANIFEST="${LUMINAIRE_PATCH_DIR}/kernel/ksu/manifests/$(resolve_android_version)-${KERNEL_VERSION}.json"

if [ ! -f "$MANIFEST" ]; then
    warn "scout: no manifest yet for kernel ${KERNEL_VERSION} — treating as no pins/candidates yet"
    MANIFEST="$(mktemp)"
    echo '{}' > "$MANIFEST"
fi

GH_API_AUTH=()
[ -n "${PERSONAL_TOKEN:-}" ] && GH_API_AUTH=(-H "Authorization: Bearer ${PERSONAL_TOKEN}")

latest_sha_or_empty() {
    local label="$1" url="$2" jq_filter="$3"
    local body_file http_code curl_exit sha auth_args=()

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
            SUSFS_GKI_BRANCH="gki-$(resolve_android_version)-${KERNEL_VERSION}"
            latest=$(latest_sha_or_empty "SuSFS (ReSukiSU pairing)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/${SUSFS_GKI_BRANCH}" '.id')
            resolve_component "susfs_resukisu" "SUSFS_RESUKISU" "$latest"
        fi
        ;;
    SUKISU)
        if [ "$SUSFS_ENABLED" = "true" ]; then
            latest=$(latest_sha_or_empty "SukiSU-Ultra (builtin)" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/commits/builtin" '.sha')
            resolve_component "sukisu_builtin" "SUKISU_BUILTIN" "$latest"

            SUSFS_GKI_BRANCH="gki-$(resolve_android_version)-${KERNEL_VERSION}"
            latest=$(latest_sha_or_empty "SuSFS (SukiSU pairing)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/${SUSFS_GKI_BRANCH}" '.id')
            resolve_component "susfs_sukisu" "SUSFS_SUKISU" "$latest"
        else
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
            latest=$(latest_sha_or_empty "KernelSU-Next (pershoot dev-susfs fork)" \
                "https://api.github.com/repos/pershoot/KernelSU-Next/commits/dev-susfs" '.sha')
            resolve_component "ksunext_susfs_fork" "KSUNEXT_SUSFS_FORK" "$latest"

            SUSFS_GKI_BRANCH_KSUNEXT="gki-$(resolve_android_version)-${KERNEL_VERSION}-dev"
            latest=$(latest_sha_or_empty "SuSFS (KSU-Next pairing, simonpunk)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/${SUSFS_GKI_BRANCH_KSUNEXT}" '.id')
            resolve_component "susfs_ksunext" "SUSFS_KSUNEXT" "$latest"
        else
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
