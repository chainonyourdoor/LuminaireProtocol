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
    # Output goes to a file, not /dev/null — wait_for_apt() tails this on
    # failure/timeout so a stuck or failed install is diagnosable instead
    # of a silent black box (see Setup Arsenal run #430: 17+ min stuck on
    # "Waiting for background apt install" with zero visibility into why).
    APT_LOG="/tmp/luminaire-apt-install.log"
    export APT_LOG
    # DPkg::Lock::Timeout: makes apt itself give up after N seconds if the
    # dpkg lock is held by another process (e.g. the runner image's own
    # apt-daily/unattended-upgrades timer), instead of blocking forever.
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
