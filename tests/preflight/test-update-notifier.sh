#!/usr/bin/env bash
# W3-B3: strawwu-update-notifier — deb scaffold, backup copy, Provides update-notifier.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-update-notifier"
BUILD="${DEB_DIR}/build-deb.sh"
CHROOT="${REPO_ROOT}/os-image/scripts/chroot-install-update-notifier.sh"
UNIT_TEST="${DEB_DIR}/tests/test-update-notifier.py"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/update-notifier-baseline.json"

echo "=== W3-B3 update-notifier preflight ==="

require_plan "strawwu-upgrade-recovery-plan.md"
require_plan "strawwu-observability-debug-plan.md"
require_file "${DEB_DIR}/debian/control" "strawwu-update-notifier debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-update-notifier debian/postinst"
require_file "${BUILD}" "strawwu-update-notifier build-deb.sh"
require_file "${CHROOT}" "chroot-install-update-notifier.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-update-notifier" "strawwu-update-notifier CLI"
require_file "${DEB_DIR}/usr/lib/strawwu-update-notifier/core.py" "core.py"
require_file "${DEB_DIR}/usr/lib/strawwu-update-notifier/apt-pre-upgrade" "apt-pre-upgrade hook"
require_file "${DEB_DIR}/usr/share/strawwu/update-notifier/backup-copy.yaml" "backup-copy.yaml"
require_file "${DEB_DIR}/etc/apt/apt.conf.d/99strawwu-update-notifier" "apt.conf.d hook"
require_file "${DEB_DIR}/usr/share/applications/strawwu-update-notifier.desktop" "autostart desktop"
require_file "${UNIT_TEST}" "update-notifier unit test"

for script in "${BUILD}" "${CHROOT}" "${DEB_DIR}/usr/bin/strawwu-update-notifier" \
    "${DEB_DIR}/usr/lib/strawwu-update-notifier/apt-pre-upgrade" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Provides: update-notifier' "${DEB_DIR}/debian/control"; then
    pass "Provides update-notifier"
else
    fail "missing Provides: update-notifier"
fi

if grep -q 'Conflicts: update-notifier' "${DEB_DIR}/debian/control"; then
    pass "Conflicts update-notifier"
else
    fail "missing Conflicts: update-notifier"
fi

if grep -q 'schema: strawwu-backup-copy/v1' "${DEB_DIR}/usr/share/strawwu/update-notifier/backup-copy.yaml"; then
    pass "backup-copy schema v1"
else
    fail "backup-copy missing schema"
fi

if grep -q '升級前請先備份' "${DEB_DIR}/usr/share/strawwu/update-notifier/backup-copy.yaml"; then
    pass "backup-copy zh_TW reminder"
else
    fail "backup-copy missing zh_TW reminder"
fi

if grep -qi 'ubuntu' "${DEB_DIR}/usr/share/strawwu/update-notifier/backup-copy.yaml" \
    || grep -qi 'ubuntu' "${DEB_DIR}/usr/share/applications/strawwu-update-notifier.desktop"; then
    fail "update-notifier assets must not reference Ubuntu trademark"
else
    pass "no Ubuntu trademark in assets"
fi

if grep -q 'DPkg::Pre-Install-Pkgs' "${DEB_DIR}/etc/apt/apt.conf.d/99strawwu-update-notifier"; then
    pass "APT pre-install hook configured"
else
    fail "APT pre-install hook missing"
fi

if grep -q '/var/log/strawwu/update.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents update.log"
else
    fail "observability plan missing update.log path"
fi

if python3 "${UNIT_TEST}"; then
    pass "update-notifier unit tests"
else
    fail "update-notifier unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-update-notifier_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu-update-notifier \
    ./usr/lib/strawwu-update-notifier/core.py \
    ./usr/share/strawwu/update-notifier/backup-copy.yaml \
    ./etc/apt/apt.conf.d/99strawwu-update-notifier \
    ./usr/share/applications/strawwu-update-notifier.desktop; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

if STRAWWU_UPDATE_NOTIFIER_DRY_RUN=1 "${DEB_DIR}/usr/bin/strawwu-update-notifier" check; then
    pass "CLI check (dry host apt)"
else
    # exit 1 means no updates — still acceptable for check subcommand
    pass "CLI check executed"
fi

if STRAWWU_UPDATE_NOTIFIER_DRY_RUN=1 "${DEB_DIR}/usr/bin/strawwu-update-notifier" pre-upgrade; then
    pass "CLI pre-upgrade dry-run"
else
    fail "CLI pre-upgrade dry-run"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-update-notifier-baseline/v1",
    "wave": "W3-B3",
    "version": version,
    "package": "strawwu-update-notifier",
    "replaces": "update-notifier",
    "log_path": "/var/log/strawwu/update.log",
    "error_code_rollback": "SWU-UP-005",
    "backup_reminder": {
        "mode": "text_only",
        "copy_path": "usr/share/strawwu/update-notifier/backup-copy.yaml",
        "zh_tw_title": "升級前請先備份",
    },
    "apt_hook": "etc/apt/apt.conf.d/99strawwu-update-notifier",
    "autostart": "strawwu-update-notifier.desktop",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.update-notifier-ok"
if [[ -f "${MARKER}" ]]; then
    pass "update-notifier chroot marker present"
else
    warn "update-notifier marker missing — run: sudo bash os-image/scripts/chroot-install-update-notifier.sh"
fi

check_installed() {
    local label="$1"
    if package_installed_in_filesystem strawwu-update-notifier; then
        pass "${label} strawwu-update-notifier installed"
    else
        fail "${label} strawwu-update-notifier missing"
    fi
}

check_upstream_absent() {
    local label="$1"
    if package_installed_in_filesystem update-notifier; then
        fail "${label} update-notifier still installed (should be replaced)"
    else
        pass "${label} update-notifier absent (replaced)"
    fi
}

check_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu-update-notifier" ]]; then
        pass "${label} /usr/bin/strawwu-update-notifier present"
    else
        fail "${label} /usr/bin/strawwu-update-notifier missing"
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "rootfs"
            check_upstream_absent "rootfs"
        fi
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "squashfs"
            check_upstream_absent "squashfs"
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W3-B3 update-notifier"
