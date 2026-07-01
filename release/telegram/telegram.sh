#!/usr/bin/env bash

# ======================================================
# 📨 RELEASE — TELEGRAM
# ======================================================

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"
TELEGRAM_MAX_FILE_BYTES=$((50 * 1024 * 1024))
CAPTION_BUILDER="${LUMINAIRE_PATCH_DIR}/release/telegram/caption.py"
BANNER_DIR="${LUMINAIRE_PATCH_DIR}/release/telegram"

# Source non-sensitive Telegram config (chat ID, thread IDs, channel ID)
# shellcheck source=release/telegram/config.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/config.sh"

# ------------------------------------------------------
# Guard clauses
# ------------------------------------------------------
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_BOT_TOKEN not set"
    return 0
fi
if [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_CHAT_ID not set"
    return 0
fi
if [ -z "${TELEGRAM_THREAD_ID_ARTIFACT:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_THREAD_ID_ARTIFACT not set"
    return 0
fi
if [ ! -f "${ZIP_PATH:-}" ]; then
    warn "Skipping Telegram: ZIP_PATH not set or file missing (ZIP_PATH='${ZIP_PATH:-}')"
    return 0
fi

# ------------------------------------------------------
# File size check
# ------------------------------------------------------
ZIP_SIZE_BYTES=$(stat -c%s "$ZIP_PATH" 2>/dev/null || stat -f%z "$ZIP_PATH" 2>/dev/null || echo 0)
if [ "$ZIP_SIZE_BYTES" -eq 0 ]; then
    warn "Skipping Telegram: could not determine size of ${ZIP_PATH}, or file is empty"
    return 0
fi
if [ "$ZIP_SIZE_BYTES" -gt "$TELEGRAM_MAX_FILE_BYTES" ]; then
    ZIP_SIZE_MB=$(( ZIP_SIZE_BYTES / 1024 / 1024 ))
    warn "Skipping Telegram: ${ZIP_NAME} is ${ZIP_SIZE_MB}MB, exceeds Telegram's 50MB sendDocument limit"
    return 0
fi

# ------------------------------------------------------
# Build display fields for caption builder
# ------------------------------------------------------
LINUX_VER="${KERNEL_VERSION}.${SUBLEVEL}"

BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM,,}"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM_DISPLAY^}"
if [ "${BUILD_SYSTEM}" = "MAKE" ] && [ -n "${CLANG_VARIANT:-}" ]; then
    BUILD_SYSTEM_DISPLAY="Make - ${CLANG_VARIANT^}"
fi

case "${ROOT_SOLUTION}" in
    VANILLA)  ROOT_SOLUTION_DISPLAY="Vanilla" ;;
    RESUKISU) ROOT_SOLUTION_DISPLAY="ReSukiSU" ;;
    SUKISU)   ROOT_SOLUTION_DISPLAY="SukiSU-Ultra" ;;
    *)        ROOT_SOLUTION_DISPLAY="${ROOT_SOLUTION}" ;;
esac

SUSFS_VER="N/A"
if [ "$SUSFS_ENABLED" = "true" ] && [ "$ROOT_SOLUTION" != "VANILLA" ]; then
    SUSFS_H="${KERNEL_SRC}/include/linux/susfs.h"
    if [ -f "$SUSFS_H" ]; then
        SUSFS_VER=$(grep -m1 'SUSFS_VERSION' "$SUSFS_H" \
            | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || true)
        if [ -n "$SUSFS_VER" ]; then
            [[ "$SUSFS_VER" == v* ]] || SUSFS_VER="v${SUSFS_VER}"
        else
            SUSFS_VER="N/A"
        fi
    fi
fi

MOUNTLESS_DISPLAY="N/A"
case ",${ADDONS}," in
    *,nomount,*)   MOUNTLESS_DISPLAY="NoMount" ;;
    *,zeromount,*) MOUNTLESS_DISPLAY="ZeroMount" ;;
esac

REKERNEL_DISPLAY="Disable"
BBG_DISPLAY="Disable"
DROIDSPACES_DISPLAY="Disable"
case ",${ADDONS}," in *,rekernel,*)    REKERNEL_DISPLAY="Enable" ;; esac
case ",${ADDONS}," in *,bbg,*)         BBG_DISPLAY="Enable" ;; esac
case ",${ADDONS}," in *,droidspaces,*) DROIDSPACES_DISPLAY="Enable" ;; esac

# ------------------------------------------------------
# Build group caption (no VARIANT_LINKS_JSON yet)
# ------------------------------------------------------
CAPTION_GROUP_FILE="/tmp/telegram_caption_group.txt"
CAPTION_CHANNEL_FILE="/tmp/telegram_caption_channel.txt"

LINUX_VER="$LINUX_VER" \
BUILD_SYSTEM_DISPLAY="$BUILD_SYSTEM_DISPLAY" \
COMPILER_STRING="${COMPILER_STRING:-N/A}" \
ENABLE_LTO="${ENABLE_LTO:-NONE}" \
ROOT_SOLUTION="${ROOT_SOLUTION:-}" \
ROOT_SOLUTION_DISPLAY="$ROOT_SOLUTION_DISPLAY" \
SUSFS_VER="$SUSFS_VER" \
MOUNTLESS_DISPLAY="$MOUNTLESS_DISPLAY" \
REKERNEL_DISPLAY="$REKERNEL_DISPLAY" \
BBG_DISPLAY="$BBG_DISPLAY" \
DROIDSPACES_DISPLAY="$DROIDSPACES_DISPLAY" \
GITHUB_SHA="${GITHUB_SHA:-}" \
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" \
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" \
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" \
python3 "$CAPTION_BUILDER" "$CAPTION_GROUP_FILE" "$CAPTION_CHANNEL_FILE" \
    || error "Telegram: caption builder failed!"

CAPTION="$(cat "$CAPTION_GROUP_FILE")"
rm -f "$CAPTION_GROUP_FILE" "$CAPTION_CHANNEL_FILE"

# ------------------------------------------------------
# Send to group topic — capture message_id
# ------------------------------------------------------
log "📤 Sending ${ZIP_NAME} to Telegram group topic..."

GROUP_MESSAGE_ID=""
attempt=1
while [ "$attempt" -le "$TELEGRAM_MAX_RETRIES" ]; do
    http_code=$(curl -s -o /tmp/telegram_response.json -w "%{http_code}" \
        --max-time "$TELEGRAM_API_TIMEOUT" \
        --retry 0 \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "message_thread_id=${TELEGRAM_THREAD_ID_ARTIFACT}" \
        -F "parse_mode=MarkdownV2" \
        -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
        -F "caption=${CAPTION}" 2>/tmp/telegram_curl_err.log) || http_code="000"

    response=$(cat /tmp/telegram_response.json 2>/dev/null || echo "")

    if [ "$http_code" = "200" ] && echo "$response" | grep -q '"ok":true'; then
        GROUP_MESSAGE_ID=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['message_id'])" 2>/dev/null || echo "")
        log "Group topic sent ✅ (message_id=${GROUP_MESSAGE_ID})"
        break
    fi

    curl_err=$(cat /tmp/telegram_curl_err.log 2>/dev/null || echo "")
    case "$http_code" in
        000|429|500|502|503|504)
            warn "Telegram group send failed: HTTP ${http_code} — will retry. ${curl_err}"
            ;;
        *)
            warn "Telegram group send FAILED: HTTP ${http_code} (non-retryable). Response: ${response}"
            break
            ;;
    esac

    if [ "$attempt" -lt "$TELEGRAM_MAX_RETRIES" ]; then
        sleep_secs=$(( 2 ** attempt ))
        log "⏳ Retrying in ${sleep_secs}s..."
        sleep "$sleep_secs"
    fi
    attempt=$(( attempt + 1 ))
done

# ------------------------------------------------------
# Save variant link for channel post agregation
# (channel post itself is handled by notify-channel job)
# ------------------------------------------------------
if [ "${RELEASE_CHANNEL:-false}" = "true" ] && [ -n "${TELEGRAM_CHANNEL_ID:-}" ]; then
    if [ -z "$GROUP_MESSAGE_ID" ]; then
        warn "Telegram: could not get group message_id — skipping variant link save"
    else
        VARIANT_KEY="${ROOT_SOLUTION}"
        if [ "${SUSFS_ENABLED:-false}" = "true" ] && [ "$ROOT_SOLUTION" != "VANILLA" ]; then
            VARIANT_KEY="${ROOT_SOLUTION}_SUSFS"
        fi

        GROUP_MSG_LINK="https://t.me/${TELEGRAM_GROUP_USERNAME}/${GROUP_MESSAGE_ID}"

        LINKS_DIR="${GITHUB_WORKSPACE}/variant-links"
        mkdir -p "$LINKS_DIR"
        LINK_FILE="${LINKS_DIR}/${VARIANT_KEY}.json"
        echo "{\"variant\":\"${VARIANT_KEY}\",\"link\":\"${GROUP_MSG_LINK}\",\"linux_ver\":\"${LINUX_VER}\",\"kernel_version\":\"${KERNEL_VERSION}\"}" > "${LINK_FILE}"
        log "Variant link saved → ${LINK_FILE} ✅"
    fi
fi

rm -f /tmp/telegram_response.json /tmp/telegram_curl_err.log

return 0
