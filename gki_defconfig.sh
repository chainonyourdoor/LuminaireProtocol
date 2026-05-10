#!/usr/bin/env bash

# ==================
# ⚙️ DEFCONFIG
# ==================

DEFCONFIG_FILE="${OUT_DIR}/.config"

log "Applying defconfig tweaks..."

config --enable  CONFIG_LTO_CLANG_THIN

log "Defconfig tweaks applied ✅"
