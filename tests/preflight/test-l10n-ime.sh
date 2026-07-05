#!/usr/bin/env bash
# W4-L10N: strawwu-l10n-ime — fcitx5 + zh_TW localization baseline.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-l10n-ime"
DESKTOP_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop"
SESSION_DIR="${REPO_ROOT}/os-image/debs/strawwu-session"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
CALAMARES_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
INSTALLER="${REPO_ROOT}/os-image/config/calamares-installer"
BUILD="${DEB_DIR}/build-deb.sh"
UNIT_TEST="${DEB_DIR}/tests/test-l10n-ime.py"
BASELINE="${BASELINES_DIR}/l10n-ime-baseline.json"
LOCALE_CONF="${CALAMARES_DIR}/etc/calamares/modules/locale.conf"

echo "=== W4-L10N l10n-ime preflight ==="

require_plan "strawwu-localization-ime-plan.md"

require_file "${DEB_DIR}/debian/control" "strawwu-l10n-ime debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-l10n-ime debian/postinst"
require_file "${BUILD}" "strawwu-l10n-ime build-deb.sh"
require_file "${DEB_DIR}/usr/share/strawwu/l10n-ime/ime-manifest.yaml" "ime-manifest.yaml"
require_file "${DEB_DIR}/usr/share/strawwu/l10n-ime/locale-policy.yaml" "locale-policy.yaml"
require_file "${DEB_DIR}/usr/share/fcitx5/default/conf/profile" "fcitx5 default profile"
require_file "${DEB_DIR}/etc/environment.d/95-strawwu-ime.conf" "environment.d IME"
require_file "${DEB_DIR}/etc/xdg/fcitx5/conf/profile" "system fcitx5 profile"
require_file "${UNIT_TEST}" "test-l10n-ime.py"

for script in "${BUILD}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'fcitx5-chewing' "${DEB_DIR}/debian/control"; then
    pass "Depends fcitx5-chewing (Bopomofo)"
else
    fail "missing fcitx5-chewing Depends"
fi

if grep -q 'fcitx5-table-cangjie5' "${DEB_DIR}/debian/control"; then
    pass "Depends fcitx5-table-cangjie5 (Cangjie)"
else
    fail "missing fcitx5-table-cangjie5 Depends"
fi

if grep -q 'fonts-noto-cjk' "${DEB_DIR}/debian/control"; then
    pass "Depends fonts-noto-cjk"
else
    fail "missing fonts-noto-cjk Depends"
fi

if grep -q 'DefaultIM=chewing' "${DEB_DIR}/usr/share/fcitx5/default/conf/profile"; then
    pass "fcitx5 profile default chewing"
else
    fail "fcitx5 profile missing DefaultIM=chewing"
fi

if grep -q 'GTK_IM_MODULE=fcitx' "${DEB_DIR}/etc/environment.d/95-strawwu-ime.conf"; then
    pass "environment.d GTK_IM_MODULE=fcitx"
else
    fail "environment.d missing GTK_IM_MODULE"
fi

if grep -q 'strawwu-l10n-ime' "${DESKTOP_DIR}/debian/control"; then
    pass "strawwu-desktop Depends strawwu-l10n-ime"
else
    fail "strawwu-desktop missing strawwu-l10n-ime Depends"
fi

if grep -qiE '\bibus\b' "${DESKTOP_DIR}/debian/control"; then
    fail "strawwu-desktop still recommends ibus (use fcitx5)"
else
    pass "strawwu-desktop has no ibus dependency"
fi

if grep -q 'strawwu-l10n-ime' "${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-l10n-ime"
else
    fail "target-manifest missing strawwu-l10n-ime"
fi

if grep -q 'zh_TW.UTF-8' "${LOCALE_CONF}"; then
    pass "calamares locale.conf includes zh_TW.UTF-8"
else
    fail "calamares locale.conf missing zh_TW.UTF-8"
fi

if grep -q 'locale: zh_TW.UTF-8' "${LOCALE_CONF}"; then
    pass "calamares default locale zh_TW.UTF-8"
else
    fail "calamares default locale not zh_TW.UTF-8"
fi

if grep -q 'zh_TW.UTF-8' "${INSTALLER}/etc/calamares/modules/locale.conf"; then
    pass "calamares-installer locale synced"
else
    fail "calamares-installer locale out of sync"
fi

if grep -q 'GTK_IM_MODULE=fcitx' "${SESSION_DIR}/usr/bin/strawwu-session"; then
    pass "strawwu-session exports IME env"
else
    fail "strawwu-session missing IME env exports"
fi

if grep -q 'test-l10n-ime:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile test-l10n-ime target"
else
    fail "Makefile missing test-l10n-ime"
fi

if python3 "${UNIT_TEST}"; then
    pass "strawwu-l10n-ime unit tests"
else
    fail "strawwu-l10n-ime unit tests"
fi

rm -rf "${DEB_DIR}/output"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${DEB_DIR}/output"/strawwu-l10n-ime_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/share/strawwu/l10n-ime/ime-manifest.yaml \
    ./usr/share/strawwu/l10n-ime/locale-policy.yaml \
    ./usr/share/fcitx5/default/conf/profile \
    ./etc/environment.d/95-strawwu-ime.conf \
    ./etc/xdg/fcitx5/conf/profile; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-l10n-ime-baseline/v1",
    "wave": "W4-L10N",
    "version": version,
    "package": "strawwu-l10n-ime",
    "framework": "fcitx5",
    "default_engine": "chewing",
    "engines": ["chewing", "cangjie5"],
    "default_locale": "zh_TW.UTF-8",
    "supported_locales": ["zh_TW.UTF-8", "en_US.UTF-8"],
    "fonts": ["fonts-noto-cjk"],
    "manifest": "usr/share/strawwu/l10n-ime/ime-manifest.yaml",
    "locale_policy": "usr/share/strawwu/l10n-ime/locale-policy.yaml",
    "environment": {
        "GTK_IM_MODULE": "fcitx",
        "QT_IM_MODULE": "fcitx",
        "XMODIFIERS": "@im=fcitx",
    },
    "replaces_ibus": True,
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W4-L10N l10n-ime"
