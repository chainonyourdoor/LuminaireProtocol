#!/usr/bin/env bash

# ==================
# 🔧 FUNCTIONS
# ==================

log() {
  echo -e "[LOG] $*"
}

error() {
  echo -e "[ERROR] $*"
  exit 1
}

config() {
  "$KERNEL_SRC/scripts/config" --file "$DEFCONFIG_FILE" "$@"
}
