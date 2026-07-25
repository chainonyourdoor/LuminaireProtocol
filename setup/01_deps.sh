#!/usr/bin/env bash

PKGS=(git curl wget zip patch rsync python3 ca-certificates aria2 pigz cpio g++ libzstd-dev \
      bc bison flex libssl-dev libelf-dev libdw-dev dwarves cmake ninja-build gcc-arm-linux-gnueabi)

MISSING=()
for pkg in "${PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -gt 0 ]; then
    log "Installing missing packages (background): ${MISSING[*]}"
    if ls ~/.apt-cache/*.deb &>/dev/null 2>&1; then
        sudo cp -rn ~/.apt-cache/. /var/cache/apt/archives/ 2>/dev/null || true
    fi
    APT_LOG="/tmp/luminaire-apt-install.log"
    export APT_LOG
    sudo apt-get -o DPkg::Lock::Timeout=60 update -qq > "$APT_LOG" 2>&1 \
        || error "apt-get update failed — see ${APT_LOG}"
    sudo apt-get -o DPkg::Lock::Timeout=60 install -y --no-install-recommends "${MISSING[@]}" >> "$APT_LOG" 2>&1 &
    APT_PID=$!
    export APT_PID
else
    log "All dependencies already installed ✅"
    APT_PID=""
    export APT_PID
fi
