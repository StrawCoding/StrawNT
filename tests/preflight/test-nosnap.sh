#!/usr/bin/env bash
# W1-F2: Verify snapd absent, meta snap Recommends masked, /snap stub only.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

echo "=== W1-F2 nosnap preflight ==="

require_plan "strawwu-flathub-plan.md"
require_file "${REPO_ROOT}/os-image/scripts/chroot-nosnap-harden.sh" "chroot-nosnap-harden.sh"
require_file "${REPO_ROOT}/docs/plans/kickoff/W1-F2-nosnap.md" "W1-F2 kickoff"

if [[ ! -x "${REPO_ROOT}/os-image/scripts/chroot-nosnap-harden.sh" ]]; then
    chmod +x "${REPO_ROOT}/os-image/scripts/chroot-nosnap-harden.sh"
    pass "chmod +x chroot-nosnap-harden.sh"
fi

NOSNAP_MARKER="${REPO_ROOT}/os-image/work/.nosnap-harden-ok"
if [[ -f "${NOSNAP_MARKER}" ]]; then
    pass "nosnap harden marker present (${NOSNAP_MARKER})"
else
    warn "nosnap harden marker missing — run: sudo bash os-image/scripts/chroot-nosnap-harden.sh"
fi

if ! has_rootfs && ! has_squashfs; then
    fail "neither rootfs nor squashfs present — run make clone-ubuntu-base first"
fi

check_snap_absent() {
    local label="$1"
    local pkg="$2"
    if package_installed_in_filesystem "${pkg}"; then
        fail "${label} still has forbidden snap package: ${pkg}"
    else
        pass "${label} absent ${pkg}"
    fi
}

check_snap_mount_stub() {
    local root="$1"
    local label="$2"
    if [[ ! -d "${root}/snap" ]]; then
        pass "${label} /snap absent (acceptable)"
        return 0
    fi
    local snap_count
    snap_count="$(find "${root}/snap" -mindepth 1 -maxdepth 1 ! -name README 2>/dev/null | wc -l || echo 0)"
    if [[ "${snap_count}" -gt 0 ]]; then
        fail "${label} /snap has ${snap_count} snap content dirs"
    elif [[ -f "${root}/snap/README" ]]; then
        pass "${label} /snap empty stub with README"
    else
        pass "${label} /snap empty stub"
    fi
}

check_apt_pin() {
    local root="$1"
    local label="$2"
    local pin="${root}/etc/apt/preferences.d/strawwu-nosnap"
    if [[ -f "${pin}" ]] && grep -q 'Pin-Priority: -1' "${pin}" \
        && grep -q 'Package: snapd' "${pin}"; then
        pass "${label} apt pin strawwu-nosnap"
    else
        fail "${label} missing apt pin ${pin}"
    fi
}

check_var_lib_snapd() {
    local root="$1"
    local label="$2"
    if [[ -d "${root}/var/lib/snapd" ]]; then
        fail "${label} /var/lib/snapd still present"
    else
        pass "${label} /var/lib/snapd absent"
    fi
}

check_meta_no_snap_depends() {
    local root="$1"
    local label="$2"
    local status="${root}/var/lib/dpkg/status"
    [[ -f "${status}" ]] || return 0

    local tmp bad=0
    tmp="$(mktemp)"
    python3 - "${status}" > "${tmp}" <<'PY'
import re, sys
status = open(sys.argv[1]).read()
meta = {"ubuntu-desktop", "ubuntu-desktop-minimal", "ubuntu-minimal", "ubuntu-standard"}
for block in re.split(r"\n(?=Package: )", status):
    m = re.match(r"^Package: (.+)$", block, re.M)
    if not m or m.group(1) not in meta:
        continue
    pkg = m.group(1)
    for field in ("Depends", "Pre-Depends"):
        fm = re.search(rf"^{field}: (.+)$", block, re.M)
        if fm and re.search(r"\bsnapd\b|\bsnap-confine\b", fm.group(1)):
            print(f"{pkg} {field} references snap")
PY
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        fail "${label} meta ${line}"
        bad=1
    done < "${tmp}"
    rm -f "${tmp}"
    if [[ "${bad}" -eq 0 ]]; then
        pass "${label} desktop meta has no snap Depends/Pre-Depends"
    fi
}

for pkg in snapd snap-confine; do
    check_snap_absent "rootfs+squashfs" "${pkg}"
done

if has_rootfs; then
    check_snap_mount_stub "${ROOTFS}" "rootfs"
    check_apt_pin "${ROOTFS}" "rootfs"
    check_var_lib_snapd "${ROOTFS}" "rootfs"
    check_meta_no_snap_depends "${ROOTFS}" "rootfs"

    for pkg in ubuntu-desktop ubuntu-desktop-minimal; do
        if package_installed_in_rootfs "${pkg}"; then
            if [[ -f "${NOSNAP_MARKER}" ]] && [[ -f "${REPO_ROOT}/os-image/work/.target-setup-ok" ]]; then
                warn "rootfs still has ${pkg} — re-run chroot-install-target-setup (W5-B4)"
            else
                pass "rootfs retained ${pkg}"
            fi
        elif [[ -f "${REPO_ROOT}/os-image/work/.target-setup-ok" ]]; then
            pass "rootfs absent ${pkg} (W5-B4 upstream meta purged)"
        else
            fail "rootfs missing required ${pkg}"
        fi
    done
fi

if has_squashfs; then
    check_snap_mount_stub "${SQUASHFS_ROOT}" "squashfs"
    check_apt_pin "${SQUASHFS_ROOT}" "squashfs"
    check_var_lib_snapd "${SQUASHFS_ROOT}" "squashfs"
    check_meta_no_snap_depends "${SQUASHFS_ROOT}" "squashfs"
fi

AUDIT_JSON="${BASELINES_DIR}/nosnap-audit.json"
if [[ -f "${AUDIT_JSON}" ]]; then
    validate_json_file "${AUDIT_JSON}"
    if python3 - "${AUDIT_JSON}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert not data.get("snapd_installed"), "audit reports snapd installed"
assert data.get("apt_pin_present"), "audit missing apt pin"
assert data.get("var_lib_snapd_absent"), "audit reports var/lib/snapd present"
assert data.get("snap_content_dirs", 1) == 0, "audit reports snap content"
PY
    then
        pass "nosnap-audit.json consistent"
    else
        fail "nosnap-audit.json inconsistent"
    fi
else
    warn "nosnap-audit.json missing — run chroot-nosnap-harden.sh"
fi

# Client libraries without snapd daemon — documented acceptable residual.
for pkg in libsnapd-glib-2-1 gir1.2-snapd-2; do
    if package_installed_in_filesystem "${pkg}"; then
        pass "client lib ${pkg} present (snapd daemon absent — acceptable)"
    fi
done

preflight_exit "W1-F2 nosnap"
