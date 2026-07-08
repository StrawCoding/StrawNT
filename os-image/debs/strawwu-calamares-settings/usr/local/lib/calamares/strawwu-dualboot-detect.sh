#!/usr/bin/env bash
# strawwu-dualboot-detect.sh — log existing OS entries via os-prober (C8 dual-boot UX).
set -euo pipefail

LOG="/var/log/strawwu-dualboot-detect.log"
MARKER="/var/lib/strawwu/installer-dualboot-detected"

mkdir -p "$(dirname "${LOG}")" "$(dirname "${MARKER}")"
: > "${LOG}"

if ! command -v os-prober >/dev/null 2>&1; then
    echo "os-prober not installed — dual-boot detect skipped" >> "${LOG}"
    exit 0
fi

mapfile -t entries < <(os-prober 2>>"${LOG}" || true)
if [[ "${#entries[@]}" -eq 0 ]]; then
    echo "no existing OS detected" >> "${LOG}"
    exit 0
fi

{
    echo "STRAWWU-DUALBOOT-DETECTED count=${#entries[@]}"
    printf '%s\n' "${entries[@]}"
} >> "${LOG}"

date -Is > "${MARKER}"
printf '%s\n' "${entries[@]}" >> "${MARKER}"
