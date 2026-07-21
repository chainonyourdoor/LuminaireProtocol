#!/usr/bin/env bash

# ======================================================
# 🔑 KSU ROOT-SOLUTION SUPPORT MAP — single source of truth
# ======================================================
# Same shape/purpose as kernel/addons/registry.sh's ADDON_SUPPORTED_VERSIONS
# and kernel/luminaire/registry.sh's LUMINAIRE_SUPPORTED_VERSIONS. This is
# the ONLY compatibility signal for root solutions now — resukisu.sh/
# sukisu.sh/ksunext.sh live once under kernel/ksu-shared/ (they have no
# real per-kernel-version logic; each fork's own setup.sh handles GKI
# version detection upstream), so "does kernel/<ver>-lts/ksu/<variant>/
# exist" is no longer a meaningful question to ask.
#
# SuSFS pairing is a separate, genuinely per-version question — still
# gated by kernel/<ver>-lts/ksu/susfs/susfs.sh existing (or erroring, for
# combinations like KSUNEXT+SUSFS that aren't wired up yet), not by
# anything in this map.
declare -A KSU_VARIANT_SUPPORTED_VERSIONS=(
    [resukisu]="5.10 5.15 6.1"
    [sukisu]="5.10 5.15 6.1"
    [ksunext]="5.10 5.15 6.1"
)

ksu_variant_supports_kernel_version() {
    local variant="$1"
    local supported="${KSU_VARIANT_SUPPORTED_VERSIONS[$variant]:-}"
    [ -z "$supported" ] && return 1
    [[ " ${supported} " == *" ${KERNEL_VERSION} "* ]]
}
