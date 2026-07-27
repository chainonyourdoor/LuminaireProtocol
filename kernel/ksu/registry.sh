#!/usr/bin/env bash

declare -A KSU_VARIANT_SUPPORTED_VERSIONS=(
    [resukisu]="5.10 5.15 6.1 6.6 6.12"
    [sukisu]="5.10 5.15 6.1 6.6 6.12"
    [ksunext]="5.10 5.15 6.1 6.6 6.12"
    [kowsu]="5.10 5.15 6.1 6.6 6.12"
)

ksu_variant_supports_kernel_version() {
    local variant="$1"
    local supported="${KSU_VARIANT_SUPPORTED_VERSIONS[$variant]:-}"
    [ -z "$supported" ] && return 1
    [[ " ${supported} " == *" ${KERNEL_VERSION} "* ]]
}
