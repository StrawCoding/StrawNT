#!/usr/bin/env bash
# install-guest.sh — guest-side Calamares install using custom Python partition module.
# Calamares 3.3.5 C++ partition module has a widget update loop that blocks the Qt event
# loop. Fix: override it with a Python job module that partitions the disk and sets
# GlobalStorage directly, running in exec-only mode.
set -uo pipefail

LOG=/tmp/strawwu-install-e2e.log
MARKER_INSTALL="STRAWWU-CALAMARES-INSTALL-OK"
TARGET_DEV="/dev/vda"

emit() {
    printf '%s\n' "$1" | sudo tee /dev/ttyS0 /dev/kmsg >/dev/null 2>&1 || true
}

log() {
    echo "[install-e2e] $*" >&2
    emit "[install-e2e] $*"
}

load_env() {
    local f="/mnt/strawwu-e2e/install-target.env"
    [[ -f "${f}" ]] && source "${f}"
    TARGET_DEV="${STRAWWU_E2E_TARGET_DEV:-${TARGET_DEV}}"
}

session_log() {
    local f
    for f in /root/.cache/calamares/session.log /home/ubuntu/.cache/calamares/session.log \
             //.cache/calamares/session.log; do
        [[ -f "${f}" ]] && { echo "${f}"; return 0; }
    done
    return 1
}

install_finished() {
    grep -aq "${MARKER_INSTALL}" /dev/kmsg 2>/dev/null && return 0
    local slog
    slog="$(session_log)" || return 1
    grep -aqE "${MARKER_INSTALL}|Finished|installation was finished|All done|Done\." "${slog}" 2>/dev/null
}

disable_auto_sleep() {
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
    systemctl mask reboot.target poweroff.target halt.target 2>/dev/null || true
    systemctl stop ubuntu-desktop-installer.service 2>/dev/null || true
    systemctl mask ubuntu-desktop-installer.service 2>/dev/null || true
    systemctl stop subiquity.service 2>/dev/null || true
    systemctl mask subiquity.service 2>/dev/null || true
    systemctl stop snap.ubuntu-desktop-installer.ubuntu-desktop-installer.service 2>/dev/null || true
    systemctl mask snap.ubuntu-desktop-installer.ubuntu-desktop-installer.service 2>/dev/null || true
    systemctl stop power-profiles-daemon.service 2>/dev/null || true
    pkill -f gsd-power 2>/dev/null || true
    sudo -u ubuntu DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
    sudo -u ubuntu DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 2>/dev/null || true
    sudo -u ubuntu DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
        gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    systemd-inhibit --what=idle:sleep:shutdown:handle-power-key:handle-suspend-key:handle-reboot-key \
        --who=strawwu-e2e --why="install E2E" sleep 7200 >/dev/null 2>&1 &
}

main() {
    load_env

    if [[ "${STRAWWU_E2E_DETACHED:-}" != "1" ]]; then
        export STRAWWU_E2E_DETACHED=1
        nohup sudo -E env STRAWWU_E2E_DETACHED=1 STRAWWU_E2E_TARGET_DEV="${TARGET_DEV}" \
            bash "$0" >>/tmp/strawwu-install-e2e-wrapper.log 2>&1 &
        emit "STRAWWU-INSTALL-E2E-DETACHED"
        exit 0
    fi

    emit "STRAWWU-INSTALL-E2E-START"
    disable_auto_sleep
    log "power management disabled"

    for _ in $(seq 1 45); do
        [[ -b "${TARGET_DEV}" ]] && break
        sleep 1
    done
    [[ -b "${TARGET_DEV}" ]] || { emit "STRAWWU-INSTALL-E2E-FAIL no-disk"; exit 1; }

    # Deploy custom settings (exec-only, Python partition module)
    sudo cp -f /mnt/strawwu-e2e/settings.conf /etc/calamares/settings.conf
    sudo cp -f /mnt/strawwu-e2e/users-e2e.conf /etc/calamares/modules/users.conf
    for cf in shellprocess_install-marker.conf shellprocess_e2e-user.conf shellprocess_bootloader-e2e.conf shellprocess_e2e-boot-prep.conf fstab.conf; do
        [[ -f /mnt/strawwu-e2e/${cf} ]] && \
            sudo cp -f /mnt/strawwu-e2e/${cf} /etc/calamares/modules/${cf}
    done

    # Override system partition + mount modules with our Python jobs
    local cal_mod_dir
    cal_mod_dir="$(find /usr/lib -type d -name modules -path '*/calamares/modules' 2>/dev/null | head -1)"
    cal_mod_dir="${cal_mod_dir:-/usr/lib/x86_64-linux-gnu/calamares/modules}"

    # Force remove then copy — verify each step
    for mod in partition mount fstab; do
        sudo rm -rf "${cal_mod_dir}/${mod}" && log "removed old ${mod} module"
        sudo cp -r /mnt/strawwu-e2e/modules/${mod} "${cal_mod_dir}/${mod}"
    done
    sudo chmod -R 755 "${cal_mod_dir}/partition" "${cal_mod_dir}/mount" "${cal_mod_dir}/fstab"

    # Verify: force overwrite individual files if cp -r failed
    if ! grep -q "partition(python)" "${cal_mod_dir}/partition/main.py" 2>/dev/null; then
        log "WARN: partition copy failed, forcing file overwrite"
        sudo mkdir -p "${cal_mod_dir}/partition"
        sudo cp -f /mnt/strawwu-e2e/modules/partition/main.py "${cal_mod_dir}/partition/main.py"
        sudo cp -f /mnt/strawwu-e2e/modules/partition/module.desc "${cal_mod_dir}/partition/module.desc"
    fi
    if ! grep -q "bind mounts" "${cal_mod_dir}/mount/main.py" 2>/dev/null; then
        log "WARN: mount copy failed, forcing file overwrite"
        sudo mkdir -p "${cal_mod_dir}/mount"
        sudo cp -f /mnt/strawwu-e2e/modules/mount/main.py "${cal_mod_dir}/mount/main.py"
        sudo cp -f /mnt/strawwu-e2e/modules/mount/module.desc "${cal_mod_dir}/mount/module.desc"
    fi
    sudo rm -rf /root/.cache/calamares /home/ubuntu/.cache/calamares 2>/dev/null || true

    # Neutralize branding slideshow to reduce Qt load
    printf 'import QtQuick 2.0\nItem { function onActivate() {} function onLeave() {} }\n' | sudo tee /usr/share/calamares/branding/strawwu/show.qml > /dev/null 2>&1 || true

    log "cal_mod_dir=${cal_mod_dir}"
    log "partition module.desc: $(cat "${cal_mod_dir}/partition/module.desc" 2>&1 | tr '\n' '|')"
    log "mount module.desc: $(cat "${cal_mod_dir}/mount/module.desc" 2>&1 | tr '\n' '|')"
    log "settings.conf seq: $(grep -A2 'sequence' /etc/calamares/settings.conf | tr '\n' '|')"

    # Set target device for partition Python module
    export STRAWWU_E2E_TARGET_DEV="${TARGET_DEV}"

    # Graphics environment
    export QT_QUICK_BACKEND=software
    export QT_OPENGL=software
    export LIBGL_ALWAYS_SOFTWARE=1
    export LANG=en_US.UTF-8
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"

    local cal_env="QT_QUICK_BACKEND=software QT_OPENGL=software LIBGL_ALWAYS_SOFTWARE=1"
    cal_env="${cal_env} LANG=${LANG} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    cal_env="${cal_env} STRAWWU_E2E_TARGET_DEV=${TARGET_DEV}"

    if command -v Xvfb >/dev/null 2>&1; then
        Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &>/dev/null &
        sleep 1
        cal_env="${cal_env} DISPLAY=:99"
        log "launching calamares exec-only Xvfb:99 TARGET_DEV=${TARGET_DEV}"
    else
        cal_env="${cal_env} QT_QPA_PLATFORM=offscreen"
        log "launching calamares exec-only offscreen TARGET_DEV=${TARGET_DEV}"
    fi

    : > "${LOG}"
    sudo -E env ${cal_env} calamares -D6 >>"${LOG}" 2>&1 &
    local cal_pid=$!

    # Background: sync Calamares log to shared mount for host-side diagnosis
    (while kill -0 "${cal_pid}" 2>/dev/null; do
        sleep 15
        cp -f "${LOG}" /mnt/strawwu-e2e/calamares-debug.log 2>/dev/null || true
        if [[ -s "${LOG}" ]]; then
            log "cal-tail: $(tail -1 "${LOG}" 2>/dev/null)"
        fi
    done
    cp -f "${LOG}" /mnt/strawwu-e2e/calamares-debug.log 2>/dev/null || true) &

    for i in $(seq 1 720); do
        install_finished && {
            cp -f "${LOG}" /mnt/strawwu-e2e/calamares-debug.log 2>/dev/null || true
            emit "${MARKER_INSTALL}"
            exit 0
        }
        if (( i % 12 == 0 )); then
            emit "STRAWWU-INSTALL-E2E-PROGRESS poll=${i}"
        fi
        if ! kill -0 "${cal_pid}" 2>/dev/null; then
            log "calamares exited early (loop=${i})"
            cp -f "${LOG}" /mnt/strawwu-e2e/calamares-debug.log 2>/dev/null || true
            tail -50 "${LOG}" | while read -r line; do log "cal: ${line}"; done
            install_finished && { emit "${MARKER_INSTALL}"; exit 0; }
            emit "STRAWWU-INSTALL-E2E-FAIL calamares-exit"
            exit 1
        fi
        sleep 5
    done

    cp -f "${LOG}" /mnt/strawwu-e2e/calamares-debug.log 2>/dev/null || true
    tail -50 "${LOG}" | while read -r line; do log "cal: ${line}"; done
    emit "STRAWWU-INSTALL-E2E-FAIL timeout"
    exit 1
}

main "$@"
