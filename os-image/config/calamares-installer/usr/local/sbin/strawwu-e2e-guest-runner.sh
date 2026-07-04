#!/usr/bin/env bash
# strawwu-e2e-guest-runner — live ISO helper for install-e2e (virtio-9p trigger, no serial inject).
set -uo pipefail

TAG="strawwu_e2e"
MNT="/mnt/strawwu-e2e"
LOG="/tmp/strawwu-e2e-guest-runner.log"

emit() {
    printf '%s\n' "$1" | tee /dev/ttyS0 /dev/kmsg >/dev/null 2>&1 || true
}

log() {
    echo "[e2e-runner] $*" >>"${LOG}"
    emit "[e2e-runner] $*"
}

mount_share() {
    modprobe 9pnet_virtio 2>/dev/null || true
    modprobe 9p 2>/dev/null || true
    mkdir -p "${MNT}"
    mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600,cache=none "${TAG}" "${MNT}" 2>>"${LOG}" \
        || mount -t 9p -o trans=virtio,cache=none "${TAG}" "${MNT}" 2>>"${LOG}"
}

run_if_trigger() {
    local trigger="$1" script="$2"
    [[ -f "${MNT}/${trigger}" ]] || return 0
    log "trigger ${trigger} found"
    [[ -x "${MNT}/${script}" || -f "${MNT}/${script}" ]] || {
        log "missing ${script} for ${trigger}"
        emit "STRAWWU-E2E-RUNNER-FAIL missing-${script}"
        return 1
    }
    log "trigger ${trigger} → ${script}"
    cp -f "${MNT}/${script}" "/tmp/${script}"
    chmod +x "/tmp/${script}"
    bash "/tmp/${script}"
}

disable_auto_sleep() {
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
    local uid1000_bus="unix:path=/run/user/1000/bus"
    sudo -u ubuntu DBUS_SESSION_BUS_ADDRESS="${uid1000_bus}" \
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
    sudo -u ubuntu DBUS_SESSION_BUS_ADDRESS="${uid1000_bus}" \
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 2>/dev/null || true
    sudo -u ubuntu DBUS_SESSION_BUS_ADDRESS="${uid1000_bus}" \
        gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
}

main() {
    emit "STRAWWU-E2E-RUNNER-START"
    disable_auto_sleep
    for _ in $(seq 1 120); do
        if mount_share 2>/dev/null; then
            break
        fi
        sleep 2
    done
    mountpoint -q "${MNT}" || {
        log "virtfs mount failed"
        emit "STRAWWU-E2E-RUNNER-FAIL virtfs"
        exit 1
    }
    emit "STRAWWU-E2E-RUNNER-MOUNTED"
    log "9p listing: $(ls -1 "${MNT}" 2>&1 | tr '\n' ' ')"

    local attempt
    for attempt in $(seq 1 30); do
        if [[ -f "${MNT}/partition-probe-trigger" ]]; then
            run_if_trigger "partition-probe-trigger" "partition-probe-guest.sh"
            exit $?
        fi
        if [[ -f "${MNT}/install-e2e-trigger" ]]; then
            run_if_trigger "install-e2e-trigger" "install-guest.sh"
            exit $?
        fi
        log "trigger not visible yet (attempt ${attempt}/30)"
        sleep 2
    done
    log "no trigger file after 30 retries — idle"
    exit 0
}

main "$@"
