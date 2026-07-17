#!/usr/bin/env bash

# ======================================================
# 📦 SETUP — APT DEPENDENCIES
# ======================================================

# Packages needed for a Make kernel build
PKGS=(git curl wget zip patch rsync python3 ca-certificates aria2 pigz cpio g++ libzstd-dev \
      bc bison flex libssl-dev libelf-dev dwarves cmake ninja-build gcc-arm-linux-gnueabi)

MISSING=()
for pkg in "${PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -gt 0 ]; then
    log "Installing missing packages (background): ${MISSING[*]}"
    if ls ~/.apt-cache/*.deb &>/dev/null 2>&1; then
        sudo cp -rn ~/.apt-cache/. /var/cache/apt/archives/ 2>/dev/null || true
    fi
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends "${MISSING[@]}" > /dev/null 2>&1 &
    APT_PID=$!
    export APT_PID
else
    log "All dependencies already installed ✅"
    APT_PID=""
    export APT_PID
fi
