#!/usr/bin/env bash

# ======================================================
# 📨 RELEASE — TELEGRAM
# ======================================================

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"      # seconds, per attempt
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"
TELEGRAM_MAX_FILE_BYTES=$((50 * 1024 * 1024))            # Bot API hard limit
TELEGRAM_CAPTION_LIMIT=1024                              # Bot API hard limit

# ------------------------------------------------------
# Guard clauses — every skip is logged, never silent
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
# File size check — Bot API hard limit is 50MB for sendDocument
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
# Build display fields
# ------------------------------------------------------
LINUX_VER="${KERNEL_VERSION}.${SUBLEVEL}"
COMPILER_DISPLAY="${COMPILER_STRING:-N/A}"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM,,}"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM_DISPLAY^}"

# Root Solution mapping
case "${ROOT_SOLUTION}" in
    VANILLA)  ROOT_SOLUTION_DISPLAY="Vanilla" ;;
    RESUKISU) ROOT_SOLUTION_DISPLAY="Resukisu" ;;
    SUKISU)   ROOT_SOLUTION_DISPLAY="Sukisu" ;;
    *)        ROOT_SOLUTION_DISPLAY="${ROOT_SOLUTION}" ;;
esac

# SuSFS version — extract from susfs.h if available
SUSFS_VER="N/A"
if [ "$SUSFS_ENABLED" = "true" ] && [ "$ROOT_SOLUTION" != "VANILLA" ]; then
    SUSFS_H="${KERNEL_SRC}/include/linux/susfs.h"
    if [ -f "$SUSFS_H" ]; then
        # Try with 'v' prefix first, then without
        SUSFS_VER=$(grep -m1 'SUSFS_VERSION' "$SUSFS_H" \
            | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || true)
        # Ensure 'v' prefix
        if [ -n "$SUSFS_VER" ]; then
            [[ "$SUSFS_VER" == v* ]] || SUSFS_VER="v${SUSFS_VER}"
        else
            SUSFS_VER="N/A"
        fi
    fi
fi

# Mountless Engine — parse from ADDONS comma-separated list
MOUNTLESS_ENGINE_DISPLAY="None"
case ",${ADDONS}," in
    *,nomount,*)   MOUNTLESS_ENGINE_DISPLAY="NoMount" ;;
    *,zeromount,*) MOUNTLESS_ENGINE_DISPLAY="ZeroMount" ;;
esac

# ------------------------------------------------------
# Escape every dynamic field before it goes inside a
# MarkdownV2 code fence (```Luminaire ... ```).
# Inside a code block, ONLY backtick (`) and backslash (\)
# need escaping — NOT the usual MarkdownV2 special chars
# like . - ! ( ) etc. Escaping those inside a code fence
# would show literal backslashes in the rendered message.
# Order matters: backslash must be escaped FIRST, otherwise
# the backslash we insert for backticks gets re-escaped.
# ------------------------------------------------------
mdv2_code_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\`/\\\`}"
    printf '%s' "$s"
}

LINUX_VER_ESC="$(mdv2_code_escape "$LINUX_VER")"
ROOT_SOLUTION_ESC="$(mdv2_code_escape "$ROOT_SOLUTION_DISPLAY")"
SUSFS_VER_ESC="$(mdv2_code_escape "$SUSFS_VER")"
MOUNTLESS_ENGINE_ESC="$(mdv2_code_escape "$MOUNTLESS_ENGINE_DISPLAY")"
KERNEL_BRANCH_ESC="$(mdv2_code_escape "$KERNEL_BRANCH")"
BUILD_SYSTEM_DISPLAY_ESC="$(mdv2_code_escape "$BUILD_SYSTEM_DISPLAY")"
COMPILER_DISPLAY_ESC="$(mdv2_code_escape "$COMPILER_DISPLAY")"
LTO_DISPLAY_ESC="$(mdv2_code_escape "${ENABLE_LTO:-NONE}")"

# Backtick-fence with a language tag right after the opening
# fence — this is what makes Telegram show the "Luminaire"
# label + Copy Code button on the rendered code block.
CAPTION="\`\`\`Luminaire
Linux            : ${LINUX_VER_ESC}
Root Solution    : ${ROOT_SOLUTION_ESC}
Susfs            : ${SUSFS_VER_ESC}
Mountless Engine : ${MOUNTLESS_ENGINE_ESC}
Branch           : ${KERNEL_BRANCH_ESC}
Build System     : ${BUILD_SYSTEM_DISPLAY_ESC}
Compiler         : ${COMPILER_DISPLAY_ESC}
LTO              : ${LTO_DISPLAY_ESC}
Date             : $(date +'%d %b %Y')
\`\`\`"

# ------------------------------------------------------
# Enforce Telegram's 1024-char caption hard limit.
# Truncate safely and re-close the code fence so MarkdownV2
# parsing doesn't break on an unterminated code block.
# ------------------------------------------------------
CAPTION_LEN=$(printf '%s' "$CAPTION" | wc -m)
if [ "$CAPTION_LEN" -gt "$TELEGRAM_CAPTION_LIMIT" ]; then
    warn "Caption is ${CAPTION_LEN} chars, exceeds Telegram's ${TELEGRAM_CAPTION_LIMIT}-char limit — truncating"
    SUFFIX=$'\n…\n```'
    KEEP=$(( TELEGRAM_CAPTION_LIMIT - ${#SUFFIX} ))
    CAPTION="$(printf '%s' "$CAPTION" | head -c "$KEEP")${SUFFIX}"
fi

# ------------------------------------------------------
# Send with retries + backoff for transient failures
# (timeouts, 429 rate-limit, 5xx server errors).
# 4xx (bad request, e.g. malformed caption) is NOT retried
# since retrying won't change the outcome.
# ------------------------------------------------------
ATTEMPT=1
SEND_OK=0

while [ "$ATTEMPT" -le "$TELEGRAM_MAX_RETRIES" ]; do
    log "📤 Sending ${ZIP_NAME} to Telegram (attempt ${ATTEMPT}/${TELEGRAM_MAX_RETRIES})..."

    HTTP_CODE=$(curl -s -o /tmp/telegram_response.json -w "%{http_code}" \
        --max-time "$TELEGRAM_API_TIMEOUT" \
        --retry 0 \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "message_thread_id=${TELEGRAM_THREAD_ID_ARTIFACT}" \
        -F "parse_mode=MarkdownV2" \
        -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
        -F "caption=${CAPTION}" 2>/tmp/telegram_curl_err.log) || HTTP_CODE="000"

    RESPONSE=$(cat /tmp/telegram_response.json 2>/dev/null || echo "")
    CURL_ERR=$(cat /tmp/telegram_curl_err.log 2>/dev/null || echo "")

    if [ "$HTTP_CODE" = "200" ] && echo "$RESPONSE" | grep -q '"ok":true'; then
        log "Artifact sent to Telegram ✅"
        SEND_OK=1
        break
    fi

    # Decide whether this is worth retrying
    case "$HTTP_CODE" in
        000)
            warn "Telegram send failed: connection/timeout error (${CURL_ERR:-no details}) — will retry"
            ;;
        429|500|502|503|504)
            warn "Telegram send failed: HTTP ${HTTP_CODE} (transient) — will retry. Response: ${RESPONSE}"
            ;;
        *)
            warn "Telegram send FAILED: HTTP ${HTTP_CODE} (non-retryable). Response: ${RESPONSE}"
            break
            ;;
    esac

    if [ "$ATTEMPT" -lt "$TELEGRAM_MAX_RETRIES" ]; then
        SLEEP_SECS=$(( 2 ** ATTEMPT ))
        log "⏳ Retrying in ${SLEEP_SECS}s..."
        sleep "$SLEEP_SECS"
    fi

    ATTEMPT=$(( ATTEMPT + 1 ))
done

if [ "$SEND_OK" -ne 1 ]; then
    log "❌ Telegram artifact delivery failed after ${TELEGRAM_MAX_RETRIES} attempt(s). Build artifact is still available in CI run."
fi

rm -f /tmp/telegram_response.json /tmp/telegram_curl_err.log

return 0
