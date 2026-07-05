#!/usr/bin/env bash
# W3-I2: strawwu-install.desktop + Calamares finished copy baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

UX_DIR="${REPO_ROOT}/os-image/debs/strawwu-live-install-ux"
CALAMARES_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
BUILD="${UX_DIR}/build-deb.sh"
OUTPUT_DIR="${UX_DIR}/output"
DESKTOP="${UX_DIR}/usr/share/applications/strawwu-install.desktop"
FINISHED_COPY="${UX_DIR}/usr/share/strawwu/installer/finished-copy.yaml"
FINISHED_CONF="${CALAMARES_DIR}/etc/calamares/modules/finished.conf"
UNIT_TEST="${UX_DIR}/tests/test-live-install-ux.py"
BASELINE="${BASELINES_DIR}/live-install-ux-baseline.json"

echo "=== W3-I2 live-install-ux preflight ==="

require_plan "strawwu-installer-plan.md"
require_file "${DESKTOP}" "strawwu-install.desktop"
require_file "${FINISHED_COPY}" "finished-copy.yaml"
require_file "${FINISHED_CONF}" "finished.conf"
require_file "${BUILD}" "build-deb.sh"
require_file "${UX_DIR}/debian/control" "debian/control"
require_file "${UX_DIR}/debian/postinst" "debian/postinst"
require_file "${UNIT_TEST}" "test-live-install-ux.py"

for script in "${BUILD}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Name=Install StrawWU' "${DESKTOP}"; then
    pass "desktop Name=Install StrawWU"
else
    fail "desktop missing Name=Install StrawWU"
fi

if grep -q 'Name\[zh_TW\]=安裝 StrawWU' "${DESKTOP}"; then
    pass "desktop zh_TW name"
else
    fail "desktop missing zh_TW name"
fi

if grep -q 'Icon=distributor-logo' "${DESKTOP}"; then
    pass "desktop Icon=distributor-logo"
else
    fail "desktop missing distributor-logo icon"
fi

if grep -q 'X-StrawWU-PrimaryInstaller=true' "${DESKTOP}"; then
    pass "desktop primary installer marker"
else
    fail "desktop missing X-StrawWU-PrimaryInstaller"
fi

if grep -qi 'ubuntu' "${DESKTOP}"; then
    fail "desktop must not reference Ubuntu trademark"
else
    pass "desktop no Ubuntu trademark"
fi

if grep -q 'Exec=.*calamares' "${DESKTOP}"; then
    pass "desktop Exec launches calamares"
else
    fail "desktop missing calamares Exec"
fi

if grep -q 'schema: strawwu-finished-copy/v1' "${FINISHED_COPY}"; then
    pass "finished-copy schema v1"
else
    fail "finished-copy missing schema"
fi

if grep -q '全部完成' "${FINISHED_COPY}" && grep -q 'zh_TW:' "${FINISHED_COPY}"; then
    pass "finished-copy zh_TW success text"
else
    fail "finished-copy missing zh_TW success text"
fi

if grep -qi 'ubuntu' "${FINISHED_COPY}"; then
    fail "finished-copy must not reference Ubuntu"
else
    pass "finished-copy no Ubuntu trademark"
fi

if grep -q 'restartNowMode: user-checked' "${FINISHED_CONF}"; then
    pass "finished.conf restartNowMode=user-checked"
else
    fail "finished.conf missing restartNowMode"
fi

if grep -q 'notifyOnFinished: true' "${FINISHED_CONF}"; then
    pass "finished.conf notifyOnFinished=true"
else
    fail "finished.conf missing notifyOnFinished"
fi

if grep -q 'systemctl -i reboot' "${FINISHED_CONF}"; then
    pass "finished.conf reboot command"
else
    fail "finished.conf missing reboot command"
fi

if grep -q 'strawwu-calamares-settings' "${UX_DIR}/debian/control"; then
    pass "live-install-ux Depends calamares-settings"
else
    fail "live-install-ux missing calamares-settings Depends"
fi

if python3 "${UNIT_TEST}"; then
    pass "live-install-ux unit tests"
else
    fail "live-install-ux unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-live-install-ux_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/share/applications/strawwu-install.desktop \
    ./usr/share/strawwu/installer/finished-copy.yaml; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

if grep -qF 'calamares.desktop' <<< "${listing}"; then
    fail "deb must not ship calamares.desktop override"
else
    pass "deb does not bundle calamares.desktop"
fi

# Rebuild calamares-settings deb so finished.conf change is packaged
cal_build="${CALAMARES_DIR}/build-deb.sh"
if STRAWWU_VERSION="${VERSION}" bash "${cal_build}" >/dev/null; then
    pass "calamares-settings rebuild with finished.conf"
else
    fail "calamares-settings rebuild failed"
fi

cal_deb="$(ls -1 "${CALAMARES_DIR}/output"/strawwu-calamares-settings_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${cal_deb}" ]]; then
    cal_listing="$(dpkg-deb -c "${cal_deb}")"
    if grep -qF './etc/calamares/modules/finished.conf' <<< "${cal_listing}" \
        && dpkg-deb -x "${cal_deb}" /tmp/strawwu-cal-finished-check \
        && grep -q 'notifyOnFinished: true' /tmp/strawwu-cal-finished-check/etc/calamares/modules/finished.conf; then
        pass "calamares-settings deb ships updated finished.conf"
        rm -rf /tmp/strawwu-cal-finished-check
    else
        rm -rf /tmp/strawwu-cal-finished-check
        fail "calamares-settings deb finished.conf stale"
    fi
fi

if has_squashfs; then
    if [[ -f "${SQUASHFS_ROOT}/usr/share/applications/calamares.desktop" ]]; then
        pass "squashfs has calamares.desktop (live-install-ux deb not yet chroot-installed)"
    fi
    if [[ -f "${SQUASHFS_ROOT}/usr/share/applications/strawwu-install.desktop" ]]; then
        pass "squashfs strawwu-install.desktop installed"
    else
        warn "strawwu-install.desktop not in squashfs — install deb in chroot when integrating ISO"
    fi
else
    warn "squashfs missing — skip filesystem install checks"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-live-install-ux-baseline/v1",
    "wave": "W3-I2",
    "version": version,
    "desktop": {
        "id": "strawwu-install.desktop",
        "name_en": "Install StrawWU",
        "name_zh_tw": "安裝 StrawWU",
        "icon": "distributor-logo",
        "exec": "sudo -E calamares -D6",
        "hide_upstream": "calamares.desktop",
    },
    "finished": {
        "conf_path": "os-image/debs/strawwu-calamares-settings/etc/calamares/modules/finished.conf",
        "copy_path": "os-image/debs/strawwu-live-install-ux/usr/share/strawwu/installer/finished-copy.yaml",
        "restartNowMode": "user-checked",
        "notifyOnFinished": True,
    },
    "package": "strawwu-live-install-ux",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W3-I2 live-install-ux"
