#!/usr/bin/env bash
# W6-HW1: Live USB smoke — run on a booted Live session (real hardware or dev VM).
# Collects machine profile + basic T1 checks; emits JSON to stdout or --output file.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

OUTPUT=""
MACHINE_ID=""
ENVIRONMENT="physical"

usage() {
    cat <<EOF
Usage: smoke-live.sh [--output FILE] [--machine-id ID] [--environment physical|dev-vm]

Run on a Live StrawWU session after USB boot. Checks:
  - live session (systemd + display manager)
  - network link
  - audio sink (if pipewire/pulse present)
  - strawwu branding (os-release / strawwu CLI)

Writes one machine entry JSON (stdout or --output).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

[[ -n "${MACHINE_ID}" ]] || MACHINE_ID="$(hostname -s 2>/dev/null || echo live-unknown)"

detect_cpu() {
    lscpu 2>/dev/null | awk -F: '/Model name/ { gsub(/^ +/, "", $2); print $2; exit }' \
        || uname -m
}

detect_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | awk -F: '/VGA compatible|3D controller/ { print $3; exit }' \
            | sed 's/^ //' || echo unknown
    else
        echo unknown
    fi
}

detect_firmware() {
    if [[ -d /sys/firmware/efi ]]; then
        echo uefi
    else
        echo legacy-bios
    fi
}

test_live_boot() {
    systemctl is-system-running --quiet 2>/dev/null \
        || systemctl is-active --quiet multi-user.target 2>/dev/null \
        && echo PASS || echo FAIL
}

test_desktop() {
    if systemctl is-active --quiet gdm.service 2>/dev/null \
        || systemctl is-active --quiet sddm.service 2>/dev/null \
        || [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        echo PASS
    else
        echo FAIL
    fi
}

test_network() {
    if ip link show up 2>/dev/null | grep -qv 'lo:'; then
        echo PASS
    else
        echo SKIP
    fi
}

test_audio() {
    if command -v pactl >/dev/null 2>&1 && pactl list sinks short 2>/dev/null | grep -q .; then
        echo PASS
    elif command -v wpctl >/dev/null 2>&1 && wpctl status 2>/dev/null | grep -qi 'sink'; then
        echo PASS
    else
        echo SKIP
    fi
}

test_branding() {
    if [[ -f /etc/os-release ]] && grep -q 'StrawWU\|strawwu' /etc/os-release 2>/dev/null; then
        echo PASS
    elif command -v strawwu >/dev/null 2>&1; then
        echo PASS
    else
        echo FAIL
    fi
}

tested="$(date -Is)"
cpu="$(detect_cpu)"
gpu="$(detect_gpu)"
firmware="$(detect_firmware)"
live_boot="$(test_live_boot)"
desktop="$(test_desktop)"
network="$(test_network)"
audio="$(test_audio)"
branding="$(test_branding)"

notes=""
if [[ "${live_boot}" != "PASS" ]]; then
    notes="live session not ready"
fi

entry_json="$(python3 - <<PY
import json
data = {
    "machine_id": "${MACHINE_ID}",
    "tier": "T1",
    "environment": "${ENVIRONMENT}",
    "cpu": """${cpu}""",
    "gpu": """${gpu}""",
    "firmware": "${firmware}",
    "usb_method": "live-smoke",
    "tests": {
        "live_boot": "${live_boot}",
        "desktop": "${desktop}",
        "network": "${network}",
        "audio": "${audio}",
        "branding": "${branding}",
    },
    "notes": """${notes}""",
    "tested": "${tested}",
}
print(json.dumps(data, ensure_ascii=False))
PY
)"

if [[ -n "${OUTPUT}" ]]; then
    printf '%s\n' "${entry_json}" > "${OUTPUT}"
    hw_log "smoke-live → ${OUTPUT} (live_boot=${live_boot})"
else
    printf '%s\n' "${entry_json}"
fi

[[ "${live_boot}" == "PASS" ]] || exit 1
