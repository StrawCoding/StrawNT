#!/usr/bin/env bash
# validate-calamares-preflight.sh — static checks before partition-probe / install-e2e.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="${REPO_ROOT}/os-image/config/calamares-installer"
ROOTFS="${REPO_ROOT}/os-image/work/rootfs"
ISO=""
FAIL=0

log() { echo "==> $*"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAIL=1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso) ISO="$2"; shift 2 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) fail "unknown arg: $1"; exit 1 ;;
    esac
done

check_file() {
    local label="$1" path="$2"
    [[ -f "${path}" ]] || { fail "${label} missing: ${path}"; return; }
    pass "${label}"
}

check_installer_overlay() {
    log "Checking calamares-installer overlay"
    check_file "installer settings.conf" "${INSTALLER}/etc/calamares/settings.conf"
    check_file "installer partition.conf" "${INSTALLER}/etc/calamares/modules/partition.conf"
    check_file "installer welcome.conf" "${INSTALLER}/etc/calamares/modules/welcome.conf"
    if grep -qE 'type:[[:space:]]*any' "${INSTALLER}/etc/calamares/modules/partition.conf"; then
        pass "installer partition.conf devices.type=any"
    else
        fail "installer partition.conf missing devices.type=any"
    fi
    if grep -qE '^- exec:' "${INSTALLER}/etc/calamares/settings.conf"; then
        pass "installer settings.conf has exec phase"
    else
        fail "installer settings.conf missing exec phase"
    fi
    if grep -qE 'include:' "${INSTALLER}/etc/calamares/modules/partition.conf" 2>/dev/null; then
        fail "installer partition.conf has custom include filter"
    else
        pass "installer partition.conf no include filter"
    fi
    check_file "e2e settings.conf" "${REPO_ROOT}/tests/install-e2e/guest/settings.conf"
    check_file "e2e partition.conf" "${REPO_ROOT}/tests/install-e2e/guest/partition.conf"
    check_file "e2e install-offscreen-settings.conf" "${REPO_ROOT}/tests/install-e2e/guest/install-offscreen-settings.conf"
    check_file "probe settings.conf" "${REPO_ROOT}/tests/install-e2e/guest/probe-settings.conf"
    if [[ -f "${INSTALLER}/etc/calamares/modules/devices.conf" ]]; then
        fail "orphan devices.conf in installer overlay"
    else
        pass "no orphan devices.conf"
    fi
}

check_rootfs() {
    [[ -d "${ROOTFS}/etc/calamares" ]] || { fail "rootfs calamares tree missing"; return; }
    log "Checking built rootfs calamares tree"
    check_file "rootfs settings.conf" "${ROOTFS}/etc/calamares/settings.conf"
    check_file "rootfs partition.conf" "${ROOTFS}/etc/calamares/modules/partition.conf"
    check_file "rootfs welcome.conf" "${ROOTFS}/etc/calamares/modules/welcome.conf"
    check_file "rootfs branding.desc" "${ROOTFS}/usr/share/calamares/branding/strawwu/branding.desc"
    if grep -qE 'type:[[:space:]]*any' "${ROOTFS}/etc/calamares/modules/partition.conf"; then
        pass "rootfs partition.conf devices.type=any"
    else
        fail "rootfs partition.conf missing devices.type=any (run sync-calamares-installer / rebuild ISO)"
    fi
    if [[ -f "${ROOTFS}/usr/bin/xdotool" ]]; then
        pass "rootfs usr/bin/xdotool"
    else
        fail "rootfs missing usr/bin/xdotool (needed for install-e2e fallback)"
    fi
}

check_iso_squashfs() {
    local iso="$1"
    local listing sq_tmp
    [[ -f "${iso}" ]] || { fail "ISO not found: ${iso}"; return; }
    log "Checking ISO squashfs calamares paths via xorriso"
    command -v xorriso >/dev/null 2>&1 || { fail "xorriso required for ISO preflight"; return; }
    command -v unsquashfs >/dev/null 2>&1 || { fail "unsquashfs required for ISO preflight"; return; }

    sq_tmp="$(mktemp -u /tmp/strawwu-sq-preflight.XXXXXX.squashfs)"
    if ! xorriso -osirrox on -indev "${iso}" \
            -extract /casper/minimal.squashfs "${sq_tmp}" >/dev/null 2>&1; then
        fail "xorriso extract minimal.squashfs failed"
        return
    fi
    listing="$(unsquashfs -l "${sq_tmp}" 2>/dev/null || true)"
    rm -f "${sq_tmp}"
    [[ -n "${listing}" ]] || { fail "cannot list ISO minimal.squashfs"; return; }

    for rel in \
        etc/calamares/settings.conf \
        etc/calamares/modules/partition.conf \
        etc/calamares/modules/welcome.conf \
        usr/share/calamares/branding/strawwu/branding.desc \
        usr/bin/xdotool; do
        if grep -qF "${rel}" <<< "${listing}"; then
            pass "ISO contains ${rel}"
        else
            fail "ISO missing ${rel}"
        fi
    done
}

check_installer_overlay
if [[ -d "${ROOTFS}/etc/calamares" ]]; then
    if [[ -f "${ROOTFS}/etc/calamares/settings.conf" ]]; then
        check_rootfs
    else
        echo "WARN: rootfs missing synced calamares settings (run sync-calamares-installer + rebuild ISO)"
    fi
fi

if [[ -n "${ISO}" ]]; then
    check_iso_squashfs "${ISO}"
elif [[ -f "${REPO_ROOT}/os-image/output/StrawWU-$(cat "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.3.0-cleanroom)-amd64.iso" ]]; then
    check_iso_squashfs "${REPO_ROOT}/os-image/output/StrawWU-$(cat "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.3.0-cleanroom)-amd64.iso"
fi

if [[ "${FAIL}" -eq 0 ]]; then
    log "validate-calamares-preflight: ALL PASS"
    exit 0
fi
log "validate-calamares-preflight: FAILED"
exit 1
