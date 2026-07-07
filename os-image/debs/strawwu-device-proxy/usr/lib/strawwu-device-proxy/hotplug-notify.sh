#!/bin/sh
# DDP2 — notify Hub/desktop when StrawWU-tagged devices are hotplugged.
ACTION="${ACTION:-unknown}"
DEVPATH="${DEVPATH:-}"
SUBSYSTEM="${SUBSYSTEM:-}"
TAGS="${TAGS:-}"
LOG="/var/log/strawwu/device-proxy.log"
CLASS="${STRAWWU_DEVICE_CLASS:-unknown}"

mkdir -p "$(dirname "${LOG}")" 2>/dev/null || true
printf '%s action=%s subsystem=%s class=%s devpath=%s tags=%s\n' \
    "$(date -Iseconds)" "${ACTION}" "${SUBSYSTEM}" "${CLASS}" "${DEVPATH}" "${TAGS}" \
    >> "${LOG}" 2>/dev/null || true

if command -v notify-send >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    case "${ACTION}" in
        add)
            notify-send -i input-usb "StrawWU Devices" "Device connected (${CLASS})" 2>/dev/null || true
            ;;
        remove)
            notify-send -i input-usb "StrawWU Devices" "Device removed (${CLASS})" 2>/dev/null || true
            ;;
    esac
fi

exit 0
