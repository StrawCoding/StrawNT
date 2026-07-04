#!/usr/bin/env bash
# partition-probe-guest.sh — guest-side Calamares partition backend probe.
set -uo pipefail

emit() {
    printf '%s\n' "$1" | sudo tee /dev/ttyS0 /dev/kmsg >/dev/null 2>&1 || true
}

log() {
    echo "[partition-probe] $*" >&2
    emit "[partition-probe] $*"
}

TARGET_DEV="/dev/vda"
ENV_FILE="/mnt/strawwu-e2e/probe-target.env"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"
TARGET_DEV="${STRAWWU_E2E_TARGET_DEV:-${TARGET_DEV}}"

log "start TARGET_DEV=${TARGET_DEV}"

for _ in $(seq 1 30); do
    [[ -b "${TARGET_DEV}" ]] && break
    sleep 1
done
[[ -b "${TARGET_DEV}" ]] || { emit "STRAWWU-PARTITION-PROBE-FAIL missing-disk"; exit 1; }

command -v sgdisk >/dev/null 2>&1 && sudo sgdisk --zap-all "${TARGET_DEV}" >/dev/null 2>&1 || true

sudo cp -f /mnt/strawwu-e2e/probe-settings.conf /etc/calamares/settings.conf
sudo cp -f /mnt/strawwu-e2e/partition.conf /etc/calamares/modules/partition.conf
sudo rm -rf /root/.cache/calamares /home/ubuntu/.cache/calamares 2>/dev/null || true

export QT_QPA_PLATFORM=offscreen
export LANG=en_US.UTF-8
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/999}"

run_calamares() {
    if command -v sudo >/dev/null 2>&1; then
        sudo -E env QT_QPA_PLATFORM="${QT_QPA_PLATFORM}" LANG="${LANG}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" calamares -D6 "$@"
    else
        env QT_QPA_PLATFORM="${QT_QPA_PLATFORM}" LANG="${LANG}" calamares -D6 "$@"
    fi
}

run_calamares >/tmp/partition-probe-calamares.log 2>&1 &
cal_pid=$!

for _ in $(seq 1 120); do
    for slog in /root/.cache/calamares/session.log /home/ubuntu/.cache/calamares/session.log /tmp/partition-probe-calamares.log; do
        [[ -f "${slog}" ]] || continue
        if grep -aqEi '0 devices left after filtering|no devices found|no partitions to install' "${slog}"; then
            tail -15 "${slog}" | while read -r line; do log "session: ${line}"; done
            kill "${cal_pid}" 2>/dev/null || true
            emit "STRAWWU-PARTITION-PROBE-FAIL no-devices"
            exit 1
        fi
        if grep -aqEi 'requirement 0 "partitions" satisfied\? true|LIST OF DETECTED DEVICES:|found [1-9][0-9]* device|suitable device| [1-9][0-9]* devices? left' "${slog}"; then
            kill "${cal_pid}" 2>/dev/null || true
            wait "${cal_pid}" 2>/dev/null || true
            pkill -x calamares 2>/dev/null || true
            emit "STRAWWU-PARTITION-PROBE-OK ${TARGET_DEV}"
            exit 0
        fi
    done
    if ! kill -0 "${cal_pid}" 2>/dev/null; then
        log "calamares exited early"
        tail -20 /tmp/partition-probe-calamares.log 2>/dev/null | while read -r line; do log "cal: ${line}"; done
        break
    fi
    sleep 2
done

log "probe timed out"
tail -20 /tmp/partition-probe-calamares.log 2>/dev/null | while read -r line; do log "cal: ${line}"; done
emit "STRAWWU-PARTITION-PROBE-FAIL timeout"
exit 1
