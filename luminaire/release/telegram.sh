#!/usr/bin/env bash

# ======================================================
# 📨 RELEASE — TELEGRAM
# ======================================================

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"
TELEGRAM_MAX_FILE_BYTES=$((50 * 1024 * 1024))
TELEGRAM_CAPTION_LIMIT=1024

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
# Build display fields
# ------------------------------------------------------
LINUX_VER="${KERNEL_VERSION}.${SUBLEVEL}"
COMPILER_DISPLAY="${COMPILER_STRING:-N/A}"

BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM,,}"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM_DISPLAY^}"
if [ "${BUILD_SYSTEM}" = "MAKE" ] && [ -n "${CLANG_VARIANT:-}" ]; then
    CLANG_LABEL="${CLANG_VARIANT^}"
    BUILD_SYSTEM_DISPLAY="Make - ${CLANG_LABEL}"
fi

# Root Solution mapping
case "${ROOT_SOLUTION}" in
    VANILLA)  ROOT_SOLUTION_DISPLAY="Vanilla" ;;
    RESUKISU) ROOT_SOLUTION_DISPLAY="ReSukiSU" ;;
    SUKISU)   ROOT_SOLUTION_DISPLAY="SukiSU-Ultra" ;;
    *)        ROOT_SOLUTION_DISPLAY="${ROOT_SOLUTION}" ;;
esac

# SuSFS version
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

# Mountless Engine
MOUNTLESS_DISPLAY="N/A"
case ",${ADDONS}," in
    *,nomount,*)   MOUNTLESS_DISPLAY="NoMount" ;;
    *,zeromount,*) MOUNTLESS_DISPLAY="ZeroMount" ;;
esac

# Addons flags
REKERNEL_DISPLAY="Disable"
BBG_DISPLAY="Disable"
DROIDSPACES_DISPLAY="Disable"
case ",${ADDONS}," in *,rekernel,*)    REKERNEL_DISPLAY="Enable" ;; esac
case ",${ADDONS}," in *,bbg,*)         BBG_DISPLAY="Enable" ;; esac
case ",${ADDONS}," in *,droidspaces,*) DROIDSPACES_DISPLAY="Enable" ;; esac

# ------------------------------------------------------
# Escape for MarkdownV2 code fence
# Inside code block only backtick and backslash need escaping
# ------------------------------------------------------
mdv2_code_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\`/\\\`}"
    printf '%s' "$s"
}

LINUX_VER_ESC="$(mdv2_code_escape "$LINUX_VER")"
KERNEL_BRANCH_ESC="$(mdv2_code_escape "$KERNEL_BRANCH")"
BUILD_SYSTEM_ESC="$(mdv2_code_escape "$BUILD_SYSTEM_DISPLAY")"
COMPILER_ESC="$(mdv2_code_escape "$COMPILER_DISPLAY")"
LTO_ESC="$(mdv2_code_escape "${ENABLE_LTO:-NONE}")"
ROOT_SOLUTION_ESC="$(mdv2_code_escape "$ROOT_SOLUTION_DISPLAY")"
SUSFS_VER_ESC="$(mdv2_code_escape "$SUSFS_VER")"
MOUNTLESS_ESC="$(mdv2_code_escape "$MOUNTLESS_DISPLAY")"
REKERNEL_ESC="$(mdv2_code_escape "$REKERNEL_DISPLAY")"
BBG_ESC="$(mdv2_code_escape "$BBG_DISPLAY")"
DROIDSPACES_ESC="$(mdv2_code_escape "$DROIDSPACES_DISPLAY")"
DATE_ESC="$(mdv2_code_escape "$(date +'%d %b %Y')")"

# ------------------------------------------------------
# Build caption — three blocks separated by newline
# Block 3 (Add-ons) is skipped if all addons are N/A
# ------------------------------------------------------
BLOCK_LUMINAIRE="\`\`\`Luminaire
Linux        : ${LINUX_VER_ESC}
Branch       : ${KERNEL_BRANCH_ESC}
Build System : ${BUILD_SYSTEM_ESC}
Compiler     : ${COMPILER_ESC}
LTO          : ${LTO_ESC}
Date         : ${DATE_ESC}
\`\`\`"

BLOCK_ROOT="\`\`\`RootSolution
KSU   : ${ROOT_SOLUTION_ESC}
SuSFS : ${SUSFS_VER_ESC}
\`\`\`"

BLOCK_ADDONS="\`\`\`Add-ons
Mountless Engine : ${MOUNTLESS_ESC}
Re:Kernel        : ${REKERNEL_ESC}
BBG              : ${BBG_ESC}
Droidspaces      : ${DROIDSPACES_ESC}
\`\`\`"

# MarkdownV2 outside code block requires escaping special chars
mdv2_escape() {
    python3 -c "
import sys
s = sys.argv[1]
special = chr(95)+chr(42)+chr(91)+chr(93)+chr(40)+chr(41)+chr(126)+chr(96)+chr(62)+chr(35)+chr(43)+chr(45)+chr(61)+chr(124)+chr(123)+chr(125)+chr(46)+chr(33)
for ch in special:
    s = s.replace(ch, chr(92) + ch)
sys.stdout.write(s)
" "$1"
}

mdv2_escape_url() {
    python3 -c "
import sys
s = sys.argv[1]
# In MarkdownV2 inline link URL (inside parentheses), only ) and \ need escaping
s = s.replace(chr(92), chr(92)+chr(92))
s = s.replace(chr(41), chr(92)+chr(41))
sys.stdout.write(s)
" "$1"
}

COMMIT_SHORT="${GITHUB_SHA:0:7}"
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

COMMIT_SHORT_ESC="$(mdv2_escape "$COMMIT_SHORT")"
COMMIT_URL_ESC="$(mdv2_escape_url "$COMMIT_URL")"
RUN_URL_ESC="$(mdv2_escape_url "$RUN_URL")"
RUN_ID_ESC="$(mdv2_escape "$GITHUB_RUN_ID")"

FOOTER="[${COMMIT_SHORT_ESC}](${COMMIT_URL_ESC}) \\| [Run \\#${RUN_ID_ESC}](${RUN_URL_ESC})"

CAPTION="${BLOCK_LUMINAIRE}
${BLOCK_ROOT}
${BLOCK_ADDONS}
${FOOTER}"

# ------------------------------------------------------
# Enforce Telegram's 1024-char caption hard limit
# ------------------------------------------------------
CAPTION_LEN=$(printf '%s' "$CAPTION" | wc -m)
if [ "$CAPTION_LEN" -gt "$TELEGRAM_CAPTION_LIMIT" ]; then
    warn "Caption is ${CAPTION_LEN} chars, exceeds Telegram's ${TELEGRAM_CAPTION_LIMIT}-char limit — truncating"
    SUFFIX=$'\n…\n```'
    KEEP=$(( TELEGRAM_CAPTION_LIMIT - ${#SUFFIX} ))
    CAPTION="$(printf '%s' "$CAPTION" | head -c "$KEEP")${SUFFIX}"
fi

# ------------------------------------------------------
# Send with retries + backoff
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
