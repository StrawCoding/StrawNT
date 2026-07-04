#!/usr/bin/env bash
# StrawWU ISO build modes — source from build-iso.sh / Makefile (do not execute standalone).
#   dev-vm       — no ISO; sync into installed VM (tests/dev-vm/)
#   dev-iso      — fast zstd squashfs for daily live/casper checks
#   release-iso  — slow xz squashfs for tags, GitHub Release, public test
set -euo pipefail

iso_mode_die() { echo "ERROR [iso-mode]: $*" >&2; exit 1; }

iso_mode_resolve() {
    local mode="${STRAWWU_ISO_MODE:-release-iso}"
    STRAWWU_ISO_MODE="${mode}"

    case "${mode}" in
        dev-vm)
            iso_mode_die "dev-vm does not build ISO — use: make dev-vm-sync / make dev-vm-test"
            ;;
        dev-iso)
            STRAWWU_SKIP_SQUASHFS="${STRAWWU_SKIP_SQUASHFS:-0}"
            STRAWWU_PREFLIGHT_STRICT="${STRAWWU_PREFLIGHT_STRICT:-0}"
            STRAWWU_BOOT_TEST_MODES="${STRAWWU_BOOT_TEST_MODES:-bios}"
            STRAWWU_MKSQUASHFS_COMP=(zstd)
            STRAWWU_MKSQUASHFS_EXTRA=(-Xcompression-level 3)
            STRAWWU_MKSQUASHFS_PROCESSORS="${STRAWWU_MKSQUASHFS_PROCESSORS:-$(nproc)}"
            ;;
        release-iso)
            if [[ "${STRAWWU_SKIP_SQUASHFS:-0}" == "1" ]]; then
                iso_mode_die "release-iso forbids STRAWWU_SKIP_SQUASHFS=1 (use dev-iso or repack-iso)"
            fi
            STRAWWU_SKIP_SQUASHFS="${STRAWWU_SKIP_SQUASHFS:-0}"
            STRAWWU_PREFLIGHT_STRICT="${STRAWWU_PREFLIGHT_STRICT:-1}"
            STRAWWU_BOOT_TEST_MODES="${STRAWWU_BOOT_TEST_MODES:-bios,uefi}"
            STRAWWU_MKSQUASHFS_COMP=(xz)
            STRAWWU_MKSQUASHFS_EXTRA=(-b 1M -Xbcj x86)
            STRAWWU_MKSQUASHFS_PROCESSORS="${STRAWWU_MKSQUASHFS_PROCESSORS:-$(nproc)}"
            ;;
        *)
            iso_mode_die "unknown STRAWWU_ISO_MODE=${mode} (want dev-vm|dev-iso|release-iso)"
            ;;
    esac

    export STRAWWU_ISO_MODE STRAWWU_SKIP_SQUASHFS STRAWWU_PREFLIGHT_STRICT STRAWWU_BOOT_TEST_MODES
    export STRAWWU_MKSQUASHFS_PROCESSORS
}

iso_mode_log() {
    echo "==> [iso-mode ${STRAWWU_ISO_MODE}] $*" >&2
}

# Build mksquashfs compression argument array into caller-named array variable.
# Usage: iso_mode_squashfs_args OUT_ARRAY_NAME
iso_mode_squashfs_args() {
    local -n _out=$1
    _out=(
        -comp "${STRAWWU_MKSQUASHFS_COMP[0]}"
        "${STRAWWU_MKSQUASHFS_EXTRA[@]}"
        -noappend
        -processors "${STRAWWU_MKSQUASHFS_PROCESSORS}"
    )
}
