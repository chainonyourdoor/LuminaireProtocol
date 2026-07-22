#!/usr/bin/env bash

# ======================================================
# 📨 RELEASE — TELEGRAM
# ======================================================

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"
TELEGRAM_MAX_FILE_BYTES=$((50 * 1024 * 1024))
CAPTION_BUILDER="${LUMINAIRE_PATCH_DIR}/release/telegram/caption.py"

# Source non-sensitive Telegram config (chat ID, thread IDs, channel ID)
# shellcheck source=release/telegram/config.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/config.sh"
# shellcheck source=release/telegram/common.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/common.sh"

# ------------------------------------------------------
# Guard clauses
# ------------------------------------------------------
if [ "${DRY_RUN:-false}" = "true" ]; then
    log "Skipping Telegram: Dry Run mode (pipeline test only)"
    return 0
fi
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_BOT_TOKEN not set"
    return 0
fi
if [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_CHAT_ID not set"
    return 0
fi
if [ ! -f "${ZIP_PATH:-}" ]; then
    warn "Skipping Telegram: ZIP_PATH not set or file missing (ZIP_PATH='${ZIP_PATH:-}')"
    return 0
fi

# Pick the destination topic from RUN_MODE. Warm Run mode never reaches this
# script (build.sh exits before run_release), and Dry Run returns above
# before this point — so only Build/Release are valid here, anything else
# is a misconfiguration, not a silent no-op.
RUN_MODE_UPPER="${RUN_MODE^^}"
case "$RUN_MODE_UPPER" in
    # Build mode has one topic per kernel version (TELEGRAM_THREAD_ID_BUILD_BY_VERSION
    # in config.sh, keyed by $KERNEL_VERSION) instead of a single shared topic.
    BUILD)     TARGET_THREAD_ID="${TELEGRAM_THREAD_ID_BUILD_BY_VERSION[$KERNEL_VERSION]:-}" ;;
    RELEASE)   TARGET_THREAD_ID="${TELEGRAM_THREAD_ID_RELEASE:-}" ;;
    *)         error "Telegram: unknown RUN_MODE '${RUN_MODE:-}' — expected Build or Release" ;;
esac
if [ -z "$TARGET_THREAD_ID" ]; then
    warn "Skipping Telegram: no thread id configured for RUN_MODE=${RUN_MODE}, KERNEL_VERSION=${KERNEL_VERSION:-}"
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

case "${KERNEL_VARIANT}" in
    VANILLA)  KERNEL_VARIANT_DISPLAY="Vanilla" ;;
    RESUKISU) KERNEL_VARIANT_DISPLAY="ReSukiSU" ;;
    SUKISU)   KERNEL_VARIANT_DISPLAY="SukiSU-Ultra" ;;
    KSUNEXT)  KERNEL_VARIANT_DISPLAY="KernelSU-Next" ;;
    *)        KERNEL_VARIANT_DISPLAY="${KERNEL_VARIANT}" ;;
esac

# Each fork resolves its own version string in its integration script
# (resukisu.sh / sukisu.sh / ksunext.sh, "Version string" step) and exports
# it via $GITHUB_ENV — pick the one matching this build's fork.
KERNEL_VARIANT_VERSION=""
case "${KERNEL_VARIANT}" in
    RESUKISU) KERNEL_VARIANT_VERSION="${RESUKISU_VERSION_DISPLAY:-}" ;;
    SUKISU)   KERNEL_VARIANT_VERSION="${SUKISU_VERSION_DISPLAY:-}" ;;
    KSUNEXT)  KERNEL_VARIANT_VERSION="${KSUNEXT_VERSION_DISPLAY:-}" ;;
esac

SUSFS_VER="N/A"
if [ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ]; then
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

# ------------------------------------------------------
# Build group caption (no VARIANT_LINKS_JSON yet)
# ------------------------------------------------------
CAPTION_GROUP_FILE="/tmp/telegram_caption_group.txt"
CAPTION_CHANNEL_FILE="/tmp/telegram_caption_channel.txt"

LINUX_VER="$LINUX_VER" \
COMPILER_STRING="${COMPILER_STRING:-N/A}" \
LTO_MODE="${LTO_MODE:-NONE}" \
RUN_MODE="${RUN_MODE:-}" \
KERNEL_VARIANT="${KERNEL_VARIANT:-}" \
KERNEL_VARIANT_DISPLAY="$KERNEL_VARIANT_DISPLAY" \
KERNEL_VARIANT_VERSION="$KERNEL_VARIANT_VERSION" \
SUSFS_VER="$SUSFS_VER" \
ADDONS="${ADDONS:-}" \
SKIPPED_ADDONS="${SKIPPED_ADDONS:-}" \
APPLIED_LUMINAIRE="${APPLIED_LUMINAIRE:-}" \
SKIPPED_LUMINAIRE="${SKIPPED_LUMINAIRE:-}" \
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
log "📤 Sending ${ZIP_NAME} to Telegram (${RUN_MODE_UPPER} topic)..."

GROUP_MESSAGE_ID=""
if telegram_api_call "sendDocument" /tmp/telegram_response.json "Telegram group send" \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "message_thread_id=${TARGET_THREAD_ID}" \
        -F "parse_mode=MarkdownV2" \
        -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
        -F "caption=${CAPTION}"; then
    GROUP_MESSAGE_ID=$(echo "$TG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['message_id'])" 2>/dev/null || echo "")
    log "Group topic sent ✅ (message_id=${GROUP_MESSAGE_ID})"
fi

# ------------------------------------------------------
# Save variant link for channel post aggregation
# (channel post itself is handled by notify-channel job, Release mode only)
# ------------------------------------------------------
if [ "$RUN_MODE_UPPER" = "RELEASE" ] && [ -n "${TELEGRAM_CHANNEL_ID:-}" ]; then
    if [ -z "$GROUP_MESSAGE_ID" ]; then
        warn "Telegram: could not get group message_id — skipping variant link save"
    else
        VARIANT_KEY="${KERNEL_VARIANT}"
        if [ "${SUSFS_ENABLED:-false}" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ]; then
            VARIANT_KEY="${KERNEL_VARIANT}_SUSFS"
        fi

        GROUP_MSG_LINK="https://t.me/${TELEGRAM_CI_GROUP}/${GROUP_MESSAGE_ID}"

        LINKS_DIR="${GITHUB_WORKSPACE}/variant-links"
        mkdir -p "$LINKS_DIR"
        LINK_FILE="${LINKS_DIR}/${VARIANT_KEY}.json"
        echo "{\"variant\":\"${VARIANT_KEY}\",\"link\":\"${GROUP_MSG_LINK}\",\"linux_ver\":\"${LINUX_VER}\",\"kernel_version\":\"${KERNEL_VERSION}\",\"ksu_version\":\"${KERNEL_VARIANT_VERSION}\",\"compiler_string\":\"${COMPILER_STRING:-}\",\"lto_mode\":\"${LTO_MODE:-}\",\"skipped_addons\":\"${SKIPPED_ADDONS:-}\",\"applied_luminaire\":\"${APPLIED_LUMINAIRE:-}\",\"skipped_luminaire\":\"${SKIPPED_LUMINAIRE:-}\"}" > "${LINK_FILE}"
        log "Variant link saved → ${LINK_FILE} ✅"
    fi
fi

rm -f /tmp/telegram_response.json

return 0
