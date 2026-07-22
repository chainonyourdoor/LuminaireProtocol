#!/usr/bin/env bash

# ======================================================
# ⚙️ TELEGRAM CONFIG
# ======================================================

TELEGRAM_CHAT_ID="-1004391786664"
TELEGRAM_CI_GROUP="LuminaireCI"       # bot notifications (Build/Release/Event topics)
TELEGRAM_GROUP="LuminaireLab"         # community discussion group

# Repository Event
TELEGRAM_THREAD_ID_EVENT="4"

# Experimental Builds — for Build mode (flash-test before being declared stable)
# One topic per kernel version. Keyed by $KERNEL_VERSION (matches the
# build.yml "Kernel Version" dropdown, e.g. "5.10"/"5.15"/"6.1") so
# telegram.sh can route without a chain of if/elif. A version without an
# entry here (e.g. 6.6/6.12 before their own topic is created) has no
# fallback — telegram.sh warns and skips the send rather than dumping an
# unrelated kernel version's build into another version's topic.
declare -A TELEGRAM_THREAD_ID_BUILD_BY_VERSION=(
    ["5.10"]="605"
    ["5.15"]="606"
    ["6.1"]="626"
)

# Release Builds — for Release mode (stable build published to the channel)
TELEGRAM_THREAD_ID_RELEASE="84"

# Telegram Channel
TELEGRAM_CHANNEL_ID="-1003777184726"
