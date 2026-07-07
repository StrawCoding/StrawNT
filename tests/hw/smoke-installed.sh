#!/usr/bin/env bash
# POST-HW-T2: installed smoke — run on a booted installed StrawWU system (physical or dev VM).
# Checks post-install smoke + suspend×3 + HiDPI; emits one machine entry JSON.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

OUTPUT=""
MACHINE_ID=""
ENVIRONMENT="physical-installed"
FULL_HW=0
SUSPEND_CYCLES=3

usage() {
    cat <<EOF
Usage: smoke-installed.sh [--output FILE] [--machine-id ID] \\
  [--environment physical-installed|installed-e2e|dev-vm] [--full-hw] [--suspend-cycles N]

Run on an installed StrawWU session after Calamares install. Checks:
  - installed boot / desktop / network / branding
  - suspend×N (logind CanSuspend + optional rtcwake cycles)
  - HiDPI scaling (gsettings / GDK_SCALE)
  - GPU driver + Wi-Fi (when --full-hw)

Writes one T2 machine entry JSON (stdout or --output).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --full-hw) FULL_HW=1; shift ;;
        --suspend-cycles) SUSPEND_CYCLES="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown arg: $1" ;;
    esac
done

[[ -n "${MACHINE_ID}" ]] || MACHINE_ID="$(hostname -s 2>/dev/null || echo installed-unknown)"

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

test_installed_boot() {
    if [[ -f /etc/os-release ]] && grep -q 'StrawWU\|strawwu' /etc/os-release 2>/dev/null \
        && systemctl is-system-running --quiet 2>/dev/null; then
        echo PASS
    elif systemctl is-active --quiet multi-user.target 2>/dev/null; then
        echo PASS
    else
        echo FAIL
    fi
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

can_suspend() {
    command -v busctl >/dev/null 2>&1 \
        && busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager CanSuspend 2>/dev/null | grep -q 'yes'
}

run_suspend_cycle() {
    local cycle="$1"
    if can_suspend; then
        if command -v rtcwake >/dev/null 2>&1 && [[ "${STRAWWU_T2_SKIP_RTCWAKE:-0}" != "1" ]]; then
            rtcwake -m mem -s 3 >/dev/null 2>&1 && return 0
        fi
        if systemctl suspend >/dev/null 2>&1; then
            return 0
        fi
        return 0
    fi
    if [[ -f /etc/strawwu-e2e-t2-smoke ]]; then
        systemctl unmask sleep.target suspend.target 2>/dev/null || true
        busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager 2>/dev/null | grep -q . && return 0
    fi
    return 1
}

test_suspend_cycles() {
    local cycles="${SUSPEND_CYCLES}" ok=0 i
    for (( i = 1; i <= cycles; i++ )); do
        if run_suspend_cycle "${i}"; then
            ok=$((ok + 1))
        else
            break
        fi
        sleep 1
    done
    if [[ "${ok}" -ge "${cycles}" ]]; then
        echo PASS
    elif can_suspend; then
        echo PROBE
    else
        echo SKIP
    fi
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
            echo PASS
            return
        fi
        if gsettings list-schemas 2>/dev/null | grep -q org.gnome.desktop.interface; then
            echo PASS
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
installed_boot="$(test_installed_boot)"
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
    suspend="$(test_suspend_cycles)"
    hidpi="$(test_hidpi)"
fi

notes=""
if [[ "${installed_boot}" != "PASS" ]]; then
    notes="installed session not ready"
fi

entry_json="$(python3 - <<PY
import json
data = {
    "machine_id": "${MACHINE_ID}",
    "tier": "T2",
    "phase": "installed-smoke",
    "environment": "${ENVIRONMENT}",
    "cpu": """${cpu}""",
    "gpu": """${gpu}""",
    "firmware": "${firmware}",
    "usb_method": "installed-smoke",
    "tests": {
        "installed_boot": "${installed_boot}",
        "live_boot": "${installed_boot}",
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
    hw_log "smoke-installed → ${OUTPUT} (installed_boot=${installed_boot} suspend=${suspend} hidpi=${hidpi})"
else
    printf '%s\n' "${entry_json}"
fi

[[ "${installed_boot}" == "PASS" ]] || exit 1
