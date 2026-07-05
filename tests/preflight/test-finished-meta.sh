#!/usr/bin/env bash
# W5-N4: strawwu-install-init meta + Calamares finished zh_TW l10n overlay.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

META_DIR="${REPO_ROOT}/os-image/debs/strawwu-install-init"
CALAMARES_DIR="${REPO_ROOT}/os-image/debs/strawwu-calamares-settings"
TARGET_DIR="${REPO_ROOT}/os-image/debs/strawwu-target-setup"
UX_DIR="${REPO_ROOT}/os-image/debs/strawwu-live-install-ux"
BUILD="${META_DIR}/build-deb.sh"
META_TEST="${META_DIR}/tests/test-meta.py"
L10N_TEST="${CALAMARES_DIR}/tests/test-l10n-finished.py"
OUTPUT_DIR="${META_DIR}/output"
BASELINE="${BASELINES_DIR}/finished-meta-baseline.json"
MANIFEST="${META_DIR}/usr/share/strawwu/install-init/install-init-manifest.yaml"
TARGET_MANIFEST="${TARGET_DIR}/usr/share/strawwu/target-setup/target-manifest.yaml"
FINISHED_CONF="${CALAMARES_DIR}/etc/calamares/modules/finished.conf"
FINISHED_COPY="${UX_DIR}/usr/share/strawwu/installer/finished-copy.yaml"
LANG_TS="${CALAMARES_DIR}/usr/share/calamares/lang/calamares_zh_TW.ts"

echo "=== W5-N4 finished-meta preflight ==="

require_plan "strawwu-install-init-plan.md"
require_plan "strawwu-localization-ime-plan.md"
require_plan "strawwu-ux-design-system.md"

require_file "${META_DIR}/debian/control" "strawwu-install-init debian/control"
require_file "${META_DIR}/debian/postinst" "strawwu-install-init debian/postinst"
require_file "${BUILD}" "strawwu-install-init build-deb.sh"
require_file "${MANIFEST}" "install-init-manifest.yaml"
require_file "${META_TEST}" "install-init test-meta.py"
require_file "${LANG_TS}" "calamares_zh_TW.ts"
require_file "${L10N_TEST}" "calamares l10n-finished unit test"
require_file "${FINISHED_CONF}" "finished.conf"
require_file "${FINISHED_COPY}" "finished-copy.yaml"

for script in "${BUILD}" "${META_TEST}" "${L10N_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Section: metapackages' "${META_DIR}/debian/control"; then
    pass "install-init Section: metapackages"
else
    fail "install-init must be Section: metapackages"
fi

for dep in strawwu-initd strawwu-target-setup strawwu-firstboot; do
    if grep -q "${dep}" "${META_DIR}/debian/control"; then
        pass "install-init Depends ${dep}"
    else
        fail "install-init missing Depends: ${dep}"
    fi
done

if grep -q 'schema: strawwu-install-init-manifest/v1' "${MANIFEST}"; then
    pass "install-init-manifest schema v1"
else
    fail "install-init-manifest missing schema"
fi

if grep -q 'strawwu-install-init' "${TARGET_MANIFEST}"; then
    pass "target-manifest includes strawwu-install-init"
else
    fail "target-manifest missing strawwu-install-init"
fi

if grep -q 'restartNowMode: user-checked' "${FINISHED_CONF}" \
    && grep -q 'notifyOnFinished: true' "${FINISHED_CONF}"; then
    pass "finished.conf restart + notify settings"
else
    fail "finished.conf missing restart/notify settings"
fi

if grep -q 'calamares_zh_TW.qm' "${FINISHED_CONF}" \
    || grep -q 'calamares_zh_TW.qm' "${MANIFEST}" \
    || grep -q 'calamares_qm' "${MANIFEST}"; then
    pass "finished l10n documents calamares_zh_TW.qm"
else
    fail "missing calamares_zh_TW.qm documentation"
fi

if grep -q '全部完成' "${FINISHED_COPY}" && grep -q '全部完成' "${LANG_TS}"; then
    pass "finished-copy aligned with calamares_zh_TW.ts"
else
    fail "finished-copy / calamares_zh_TW.ts mismatch"
fi

if grep -qE 'firstboot.*zh_TW|firstboot_yaml' "${MANIFEST}"; then
    pass "install-init manifest documents firstboot YAML l10n"
else
    fail "install-init manifest missing firstboot l10n path"
fi

if grep -qi 'ubuntu' "${LANG_TS}"; then
    fail "calamares_zh_TW.ts must not reference Ubuntu trademark"
else
    pass "no Ubuntu trademark in calamares_zh_TW.ts"
fi

if grep -q 'L10N2' "${PLANS_DIR}/strawwu-localization-ime-plan.md"; then
    pass "localization plan defines L10N2 gettext scope"
else
    fail "localization plan missing L10N2"
fi

if python3 "${META_TEST}"; then
    pass "install-init meta unit tests"
else
    fail "install-init meta unit tests"
fi

if python3 "${L10N_TEST}"; then
    pass "calamares finished l10n unit tests"
else
    fail "calamares finished l10n unit tests"
fi

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "install-init build-deb.sh succeeded"
else
    fail "install-init build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-install-init_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "install-init deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/share/strawwu/install-init/install-init-manifest.yaml \
    ./usr/share/calamares/branding/strawwu/lang/calamares-strawwu_zh_TW.qm; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

cal_deb="$(ls -1 "${CALAMARES_DIR}/output"/strawwu-calamares-settings_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -z "${cal_deb}" || ! -f "${cal_deb}" ]]; then
    rm -rf "${CALAMARES_DIR}/output"
    STRAWWU_VERSION="${VERSION}" bash "${CALAMARES_DIR}/build-deb.sh"
    cal_deb="$(ls -1 "${CALAMARES_DIR}/output"/strawwu-calamares-settings_"${VERSION}"_all.deb 2>/dev/null | head -1)"
fi

if [[ -n "${cal_deb}" && -f "${cal_deb}" ]]; then
    cal_listing="$(dpkg-deb -c "${cal_deb}")"
    if grep -qF './usr/share/calamares/lang/calamares_zh_TW.qm' <<< "${cal_listing}"; then
        pass "calamares-settings deb ships calamares_zh_TW.qm"
    else
        fail "calamares-settings deb missing calamares_zh_TW.qm"
    fi
    if grep -qF './usr/share/calamares/lang/calamares_zh_TW.ts' <<< "${cal_listing}"; then
        pass "calamares-settings deb ships calamares_zh_TW.ts source"
    else
        fail "calamares-settings deb missing calamares_zh_TW.ts"
    fi
else
    fail "calamares-settings deb build failed"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-finished-meta-baseline/v1",
    "wave": "W5-N4",
    "version": version,
    "package": "strawwu-install-init",
    "depends": ["strawwu-initd", "strawwu-target-setup", "strawwu-firstboot"],
    "manifest": "usr/share/strawwu/install-init/install-init-manifest.yaml",
    "target_manifest_entry": "strawwu-install-init",
    "calamares": {
        "finished_conf": "etc/calamares/modules/finished.conf",
        "lang_qm": "usr/share/calamares/lang/calamares_zh_TW.qm",
        "lang_ts": "usr/share/calamares/lang/calamares_zh_TW.ts",
        "finished_copy": "usr/share/strawwu/installer/finished-copy.yaml",
    },
    "firstboot_l10n": "usr/share/strawwu/locale/firstboot.zh_TW.yaml",
    "lifecycle": ["initd", "target_setup", "firstboot"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

if has_rootfs || has_squashfs; then
    check_qm() {
        local root="$1"
        local label="$2"
        if [[ -f "${root}/usr/share/calamares/lang/calamares_zh_TW.qm" ]]; then
            pass "${label} calamares_zh_TW.qm present"
        else
            warn "${label} calamares_zh_TW.qm missing — re-run calamares-settings chroot install"
        fi
    }
    if has_squashfs; then
        check_qm "${SQUASHFS_ROOT}" "squashfs"
    fi
    if has_rootfs; then
        check_qm "${ROOTFS}" "rootfs"
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem qm checks"
fi

preflight_exit "W5-N4 finished-meta"
