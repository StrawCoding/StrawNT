#!/usr/bin/env bash
# verify-boot-chain.sh — Check SB route readiness (tools + optional artifact verify).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_DIR="${STRAWWU_SB_BOOT_DIR:-/boot}"
JSON=0

usage() {
    echo "Usage: verify-boot-chain.sh [--json] [--boot-dir DIR]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON=1; shift ;;
        --boot-dir) BOOT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

sb_state="unknown"
if command -v mokutil >/dev/null 2>&1; then
    sb_state="$(mokutil --sb-state 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)"
fi

tools=()
for t in mokutil sbsign sbverify pesign; do
    if command -v "${t}" >/dev/null 2>&1; then
        tools+=("${t}")
    fi
done

artifacts=()
for name in shim.efi grubx64.efi vmlinuz initrd.img; do
    found=""
    for candidate in \
        "${BOOT_DIR}/EFI/BOOT/${name}" \
        "${BOOT_DIR}/${name}"; do
        if [[ -f "${candidate}" ]]; then
            found="${candidate}"
            break
        fi
    done
    if [[ -n "${found}" ]]; then
        artifacts+=("${found}")
    fi
done

enforced="${STRAWWU_SECURE_BOOT_ENFORCE:-0}"
route_ok=1
if [[ "${enforced}" == "1" && ${#artifacts[@]} -lt 2 ]]; then
    route_ok=0
fi

if [[ "${JSON}" -eq 1 ]]; then
    python3 - "${sb_state}" "${enforced}" "${route_ok}" "${tools[*]}" "${artifacts[*]}" <<'PY'
import json, sys
sb_state, enforced, route_ok, tools_s, arts_s = sys.argv[1:6]
print(json.dumps({
    "schema": "strawwu-sb-verify/v1",
    "secure_boot_state": sb_state.strip(),
    "enforced": enforced == "1",
    "route_ok": bool(int(route_ok)),
    "tools": tools_s.split() if tools_s else [],
    "artifacts": arts_s.split() if arts_s else [],
}, indent=2))
PY
else
    echo "=== StrawWU Secure Boot verify ==="
    echo "sb_state: ${sb_state}"
    echo "enforced: ${enforced}"
    echo "tools: ${tools[*]:-none}"
    echo "artifacts: ${artifacts[*]:-none}"
    echo "route_ok: ${route_ok}"
fi

exit $((1 - route_ok))
