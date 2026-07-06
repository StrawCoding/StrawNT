#!/usr/bin/env bash
# W6-HW1 / W8-HW-MATRIX: Live smoke — run on a booted Live session (real hardware or dev VM).
# Collects machine profile + T1/HW3 checks; emits JSON to stdout or --output file.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

OUTPUT=""
MACHINE_ID=""
ENVIRONMENT="physical"
FULL_HW=0

usage() {
    cat <<EOF
Usage: smoke-live.sh [--output FILE] [--machine-id ID] [--environment physical|dev-vm] [--full-hw]

Run on a Live StrawWU session after USB boot. Checks:
  - live session (systemd + display manager)
  - network link / Wi-Fi
  - GPU driver (/dev/dri)
  - suspend probe (logind CanSuspend, no actual suspend)
  - HiDPI scaling (gsettings)
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
        --full-hw) FULL_HW=1; shift ;;
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

test_wifi() {
    if command -v nmcli >/dev/null 2>&1; then
        if nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | grep -E 'wifi:connected|:wifi:.*connected'; then
            echo PASS
            return
        fi
        if nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep -q ':wifi:'; then
            echo PROBE
            return
        fi
    fi
    if command -v iw >/dev/null 2>&1 && iw dev 2>/dev/null | grep -q Interface; then
        echo PROBE
        return
    fi
    if ip link show 2>/dev/null | grep -qE 'wl|wlan'; then
        echo PROBE
        return
    fi
    if test_network | grep -q PASS; then
        echo PROBE
        return
    fi
    echo SKIP
}

test_gpu_driver() {
    if [[ -e /dev/dri/card0 ]]; then
        echo PASS
    elif lsmod 2>/dev/null | grep -qE 'i915|amdgpu|nouveau|nvidia'; then
        echo PASS
    else
        echo FAIL
    fi
}

test_suspend() {
    if command -v busctl >/dev/null 2>&1; then
        local can
        can="$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager CanSuspend 2>/dev/null || true)"
        if echo "${can}" | grep -q 'yes'; then
            echo PROBE
            return
        fi
        if echo "${can}" | grep -q 'no'; then
            echo SKIP
            return
        fi
    fi
    if systemctl is-enabled sleep.target 2>/dev/null | grep -q masked; then
        echo SKIP
        return
    fi
    echo SKIP
}

test_hidpi() {
    local scale=""
    if command -v gsettings >/dev/null 2>&1; then
        scale="$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null || true)"
        if [[ -n "${scale}" && "${scale}" != "1.0" && "${scale}" != "1" ]]; then
            echo PASS
            return
        fi
        scale="$(gsettings get org.gnome.mutter experimental-features 2>/dev/null || true)"
        if echo "${scale}" | grep -qi scale; then
            echo PROBE
            return
        fi
    fi
    if [[ -n "${GDK_SCALE:-}" && "${GDK_SCALE}" != "1" ]]; then
        echo PASS
        return
    fi
    echo PROBE
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

wifi="SKIP"
gpu_driver="SKIP"
suspend="SKIP"
hidpi="SKIP"
if [[ "${FULL_HW}" -eq 1 || "${ENVIRONMENT}" != "qemu-proxy" ]]; then
    wifi="$(test_wifi)"
    gpu_driver="$(test_gpu_driver)"
    suspend="$(test_suspend)"
    hidpi="$(test_hidpi)"
fi

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
        "wifi": "${wifi}",
        "gpu_driver": "${gpu_driver}",
        "suspend": "${suspend}",
        "hidpi": "${hidpi}",
    },
    "notes": """${notes}""",
    "tested": "${tested}",
}
print(json.dumps(data, ensure_ascii=False))
PY
)"

if [[ -n "${OUTPUT}" ]]; then
    printf '%s\n' "${entry_json}" > "${OUTPUT}"
    hw_log "smoke-live → ${OUTPUT} (live_boot=${live_boot} wifi=${wifi} gpu=${gpu_driver})"
else
    printf '%s\n' "${entry_json}"
fi

[[ "${live_boot}" == "PASS" ]] || exit 1
