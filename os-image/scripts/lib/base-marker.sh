#!/usr/bin/env bash
# base-marker.sh — shared rootfs base marker checks (clone | fork).
#
# Markers:
#   .clone-ubuntu-base-ok  — cleanroom clone path
#   .fork-sync-base-ok     — fork snapshot/seed path
set -euo pipefail

base_marker_clone() {
    local work_dir="${1:?work_dir required}"
    echo "${work_dir}/.clone-ubuntu-base-ok"
}

base_marker_fork() {
    local work_dir="${1:?work_dir required}"
    echo "${work_dir}/.fork-sync-base-ok"
}

base_marker_present() {
    local work_dir="${1:?work_dir required}"
    [[ -f "$(base_marker_fork "${work_dir}")" || -f "$(base_marker_clone "${work_dir}")" ]]
}

base_marker_mode() {
    local work_dir="${1:?work_dir required}"
    if [[ -f "$(base_marker_fork "${work_dir}")" ]]; then
        echo fork
    elif [[ -f "$(base_marker_clone "${work_dir}")" ]]; then
        echo clone
    else
        echo none
    fi
}

die_unless_base_marker() {
    local work_dir="${1:?work_dir required}"
    if base_marker_present "${work_dir}"; then
        return 0
    fi
    echo "ERROR: run make clone-ubuntu-base or make fork-sync-base first" >&2
    exit 1
}
