#!/usr/bin/env bash

# ======================================================
# 📲 RELEASE — TELEGRAM NOTIFICATION
# ======================================================

[ -z "${TELEGRAM_BOT_TOKEN:-}" ] && return
[ -z "${TELEGRAM_CHAT_ID:-}" ] && return
[ -z "${TELEGRAM_THREAD_ID_ARTIFACT:-}" ] && return
[ ! -f "${ZIP_PATH:-}" ] && return

LINUX_VER="${KERNEL_VERSION}.${SUBLEVEL}"
COMPILER_DISPLAY="$([ "$BUILD_SYSTEM" = "KLEAF" ] && echo "AOSP Clang" || echo "${COMPILER_STRING:-N/A}")"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM,,}"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM_DISPLAY^}"

# Root Solution mapping
case "${VARIANT}" in
    VANILLA)         ROOT_SOLUTION="Vanilla" ;;
    RESUKISU_SUSFS)  ROOT_SOLUTION="Resukisu" ;;
    *)               ROOT_SOLUTION="${VARIANT}" ;;
esac

# SuSFS version — extract from susfs.h if available
SUSFS_VER="N/A"
if [ "$VARIANT" != "VANILLA" ]; then
    SUSFS_H="${KERNEL_SRC}/include/linux/susfs.h"
    if [ -f "$SUSFS_H" ]; then
        SUSFS_VER=$(grep -m1 'SUSFS_VERSION' "$SUSFS_H" \
            | grep -oP 'v\d+\.\d+\.\d+' | head -1 || echo "N/A")
    fi
fi

CAPTION="<b>Luminaire</b>
<code>Linux         : ${LINUX_VER}
Root Solution : ${ROOT_SOLUTION}
Susfs         : ${SUSFS_VER}
Branch        : ${KERNEL_BRANCH}
Build System  : ${BUILD_SYSTEM_DISPLAY}
Compiler      : ${COMPILER_DISPLAY}
LTO           : ${ENABLE_LTO:-NONE}
Date          : $(date +'%d %b %Y')</code>"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "message_thread_id=${TELEGRAM_THREAD_ID_ARTIFACT}" \
    -F "parse_mode=HTML" \
    -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
    -F "caption=${CAPTION}" > /dev/null || true
log "Artifact sent to Telegram ✅"
