#!/usr/bin/env bash

# ======================================================
# 📢 RELEASE — TELEGRAM CHANNEL POST
# ======================================================
# Aggregates all variant links and sends a single photo post to the channel.
# Called from the notify-channel job after all builds have finished.

CAPTION_BUILDER="${LUMINAIRE_PATCH_DIR}/release/telegram/caption.py"
TELEGRAPH_BUILDER="${LUMINAIRE_PATCH_DIR}/release/telegram/telegraph_page.py"
BANNER_DIR="${LUMINAIRE_PATCH_DIR}/release/telegram"

# Run standalone (bash release/telegram/channel_post.sh) from notify-channel,
# unlike telegram.sh which is sourced from build.sh's run_release() — so
# log/warn/error/retry() aren't in scope until sourced explicitly here.
# shellcheck source=functions.sh
source "${LUMINAIRE_PATCH_DIR}/functions.sh"
# Source non-sensitive Telegram config
# shellcheck source=release/telegram/config.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/config.sh"
# shellcheck source=release/telegram/common.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/common.sh"

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"

# ------------------------------------------------------
# Guard clauses
# ------------------------------------------------------
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping channel post: TELEGRAM_BOT_TOKEN not set"
    exit 0
fi
if [ -z "${TELEGRAM_CHANNEL_ID:-}" ]; then
    warn "Skipping channel post: TELEGRAM_CHANNEL_ID not set in config.sh"
    exit 0
fi

# ------------------------------------------------------
# Find banner
# ------------------------------------------------------
BANNER_PATH=""
for ext in jpg jpeg png; do
    candidate="${BANNER_DIR}/banner.${ext}"
    if [ -f "$candidate" ]; then
        BANNER_PATH="$candidate"
        break
    fi
done

if [ -z "$BANNER_PATH" ]; then
    warn "Skipping channel post: no banner found in ${BANNER_DIR}"
    exit 0
fi

# ------------------------------------------------------
# Collect variant links from artifact JSON files
# Expects: LINKS_DIR env var pointing to dir with *.json files
# Each JSON: {"variant": "VANILLA", "link": "https://t.me/c/..."}
# ------------------------------------------------------
LINKS_DIR="${LINKS_DIR:-/tmp/variant-links}"

if [ ! -d "$LINKS_DIR" ]; then
    warn "Skipping channel post: LINKS_DIR not found (${LINKS_DIR})"
    exit 0
fi

# Parse all variant JSON files — extract links, linux_ver, kernel_version,
# and (where present) ksu_version per variant. compiler_string and
# lto_mode are release-wide constants (single global workflow inputs, not
# per-variant — see telegram.sh where they're written), so the first
# non-empty value wins, same as linux_ver/kernel_version below.
LINKS_PARSED=$(python3 -c "
import json, glob, sys
links_dir = '${LINKS_DIR}'
result = {}
versions = {}
linux_ver = ''
kernel_version = ''
compiler_string = ''
lto_mode = ''
for f in sorted(glob.glob(links_dir + '/*.json')):
    try:
        data = json.load(open(f))
        v = data.get('variant',''); l = data.get('link','')
        if v and l:
            result[v] = l
        kv = data.get('ksu_version','')
        if v and kv:
            versions[v] = kv
        if not linux_ver: linux_ver = data.get('linux_ver','')
        if not kernel_version: kernel_version = data.get('kernel_version','')
        if not compiler_string: compiler_string = data.get('compiler_string','')
        if not lto_mode: lto_mode = data.get('lto_mode','')
    except Exception as e:
        print('[warn] ' + str(e), file=sys.stderr)
print(json.dumps({'links':result,'versions':versions,'linux_ver':linux_ver,'kernel_version':kernel_version,'compiler_string':compiler_string,'lto_mode':lto_mode}))
")

VARIANT_LINKS_JSON=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['links']))")
VARIANT_VERSIONS_JSON=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['versions']))")
LINUX_VER=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['linux_ver'])")
KERNEL_VERSION=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['kernel_version'])")
COMPILER_STRING=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['compiler_string'])")
LTO_MODE=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['lto_mode'])")
export LINUX_VER KERNEL_VERSION COMPILER_STRING LTO_MODE

if [ "$VARIANT_LINKS_JSON" = "{}" ] || [ -z "$VARIANT_LINKS_JSON" ]; then
    warn "Skipping channel post: no valid variant links found"
    exit 0
fi

log "Variant links: $VARIANT_LINKS_JSON"
log "Linux version: $LINUX_VER | Kernel: $KERNEL_VERSION"

# ------------------------------------------------------
# Diff: variants selected for this run vs. variants that actually
# produced a download link. Release mode is only ever triggered after a
# Test run already confirmed every selected variant is fine — so if a
# variant that was selected here doesn't have a link, its matrix job
# failed unexpectedly for *this* run (e.g. a checkpoint pin expired
# between Test and Release, or an upstream regression). That's exactly
# the situation a Release-mode failure should stay loud about instead of
# quietly shipping a partial channel post — so this hard-fails the whole
# job rather than posting whatever succeeded. Skipping the channel post
# on any mismatch also means a stale manual CHANGELOG mention of the
# failed variant never reaches the channel in the first place.
# ------------------------------------------------------
MISSING_VARIANTS_JSON=$(VARIANT_LINKS_JSON="$VARIANT_LINKS_JSON" python3 -c "
import json, os
matrix_json = os.environ.get('EXPECTED_MATRIX_JSON', '')
links = json.loads(os.environ.get('VARIANT_LINKS_JSON', '') or '{}')
missing = []
if matrix_json:
    try:
        matrix = json.loads(matrix_json)
        for entry in matrix.get('include', []):
            variant = entry.get('kernel_variant', '')
            susfs = entry.get('susfs', False)
            key = variant
            if susfs and variant != 'VANILLA':
                key = f'{variant}_SUSFS'
            if key and key not in links:
                missing.append(key)
    except Exception as e:
        print(f'[warn] {e}', file=__import__('sys').stderr)
print(json.dumps(missing))
")

if [ "$MISSING_VARIANTS_JSON" != "[]" ]; then
    error "Aborting channel post: variant(s) selected but missing a download link — ${MISSING_VARIANTS_JSON}. Check the Start-Build job for that variant before re-running Release."
fi

# ------------------------------------------------------
# Create per-release Telegraph Features page
# Never fails the job: telegraph_page.py always exits 0 and prints an
# empty line on failure (missing token, API down, retries exhausted) —
# caption.py's build_channel_caption() falls back to plain text pointing
# at the zip caption's Add-ons block when FEATURES_URL is empty.
# ------------------------------------------------------
FEATURES_URL=$(
    LINUX_VER="${LINUX_VER:-N/A}" \
    KERNEL_VERSION="${KERNEL_VERSION:-}" \
    ADDONS="${ADDONS:-}" \
    COMPILER_STRING="${COMPILER_STRING:-}" \
    LTO_MODE="${LTO_MODE:-}" \
    TELEGRAPH_TOKEN="${TELEGRAPH_TOKEN:-}" \
    python3 "$TELEGRAPH_BUILDER"
)

if [ -n "$FEATURES_URL" ]; then
    log "Features page: $FEATURES_URL"
else
    warn "No Features page this run — channel caption will fall back to the zip's Add-ons block"
fi

# ------------------------------------------------------
# Build channel caption
# ------------------------------------------------------
CAPTION_GROUP_DUMMY="/tmp/channel_post_group_dummy.txt"
CAPTION_CHANNEL_FILE="/tmp/channel_post_caption.txt"

LINUX_VER="${LINUX_VER:-N/A}" \
KERNEL_VERSION="${KERNEL_VERSION:-}" \
ADDONS="${ADDONS:-}" \
CHANGELOG="${CHANGELOG:-}" \
TELEGRAM_GROUP="${TELEGRAM_GROUP:-}" \
GITHUB_SHA="${GITHUB_SHA:-}" \
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" \
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" \
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" \
VARIANT_LINKS_JSON="$VARIANT_LINKS_JSON" \
VARIANT_VERSIONS_JSON="$VARIANT_VERSIONS_JSON" \
FEATURES_URL="$FEATURES_URL" \
RUN_MODE="Release" \
python3 "$CAPTION_BUILDER" "$CAPTION_GROUP_DUMMY" "$CAPTION_CHANNEL_FILE" \
    || error "Caption builder failed"

CAPTION_CHANNEL="$(cat "$CAPTION_CHANNEL_FILE")"
rm -f "$CAPTION_CHANNEL_FILE" "$CAPTION_GROUP_DUMMY"

# ------------------------------------------------------
# Send photo to channel
# ------------------------------------------------------
log "📸 Sending channel post..."
if telegram_api_call "sendPhoto" /tmp/tg_channel_response.json "Channel send" \
        -F "chat_id=${TELEGRAM_CHANNEL_ID}" \
        -F "parse_mode=MarkdownV2" \
        -F "photo=@${BANNER_PATH}" \
        -F "caption=${CAPTION_CHANNEL}"; then
    log "Channel post sent ✅"
fi

rm -f /tmp/tg_channel_response.json
