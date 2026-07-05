#!/usr/bin/env bash
# W2-B2: strawwu-bug-reporter — deb scaffold, privacy filter, bundle CLI, rootfs state.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-bug-reporter"
BUILD="${DEB_DIR}/build-deb.sh"
CHROOT="${REPO_ROOT}/os-image/scripts/chroot-install-bug-reporter.sh"
UNIT_TEST="${DEB_DIR}/tests/test-privacy-filter.py"
OUTPUT_DIR="${DEB_DIR}/output"

echo "=== W2-B2 bug-reporter preflight ==="

require_plan "strawwu-observability-debug-plan.md"
require_plan "strawwu-security-trust-model.md"
require_file "${DEB_DIR}/debian/control" "strawwu-bug-reporter debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-bug-reporter debian/postinst"
require_file "${BUILD}" "strawwu-bug-reporter build-deb.sh"
require_file "${CHROOT}" "chroot-install-bug-reporter.sh"
require_file "${DEB_DIR}/usr/bin/strawwu-bug-report" "strawwu-bug-report CLI"
require_file "${DEB_DIR}/usr/bin/strawwu-bug-report-gtk" "strawwu-bug-report-gtk"
require_file "${DEB_DIR}/usr/lib/strawwu-bug-reporter/bundle.py" "bundle.py"
require_file "${DEB_DIR}/usr/lib/strawwu-bug-reporter/filter.py" "filter.py"
require_file "${DEB_DIR}/usr/lib/strawwu-bug-reporter/consent_gtk.py" "consent_gtk.py"
require_file "${UNIT_TEST}" "privacy filter unit test"

for script in "${BUILD}" "${CHROOT}" "${DEB_DIR}/usr/bin/strawwu-bug-report" \
    "${DEB_DIR}/usr/bin/strawwu-bug-report-gtk" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'upload_opt_in=false' "${DEB_DIR}/debian/postinst"; then
    pass "postinst default upload_opt_in=false"
else
    fail "postinst missing default upload opt-out"
fi

if grep -q 'consent_required' "${PLANS_DIR}/strawwu-security-trust-model.md" \
    || grep -q 'consent' "${PLANS_DIR}/strawwu-security-trust-model.md"; then
    pass "security trust model documents consent"
else
    fail "security trust model missing consent docs"
fi

# Unit tests (privacy filter + bundle schema)
if python3 "${UNIT_TEST}"; then
    pass "privacy filter unit tests"
else
    fail "privacy filter unit tests"
fi

# Build deb on host
rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-bug-reporter_"${VERSION}"_all.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

# CLI dry-run + bundle on host
tmp_bundle="$(mktemp --suffix=.strawwu-bug)"
trap 'rm -f "${tmp_bundle}"' EXIT
if "${DEB_DIR}/usr/bin/strawwu-bug-report" --dry-run; then
    pass "CLI dry-run"
else
    fail "CLI dry-run"
fi

if "${DEB_DIR}/usr/bin/strawwu-bug-report" -o "${tmp_bundle}" --notes "preflight"; then
    pass "CLI bundle create"
else
    fail "CLI bundle create"
fi

if "${DEB_DIR}/usr/bin/strawwu-bug-report" --validate "${tmp_bundle}"; then
    pass "CLI bundle validate"
else
    fail "CLI bundle validate"
fi

# Update obs baseline: schema_ready true when bug reporter present
python3 - "${BASELINES_DIR}/obs-baseline.json" "${VERSION}" <<'PY'
import json, sys
from pathlib import Path

out, version = sys.argv[1:3]
data = {
    "schema": "strawwu-obs-baseline/v1",
    "generated_at": "2026-07-05",
    "version": version,
    "log_paths": {
        "boot-selfcheck": "/var/log/strawwu/boot-selfcheck.log",
        "install": "/var/log/strawwu/install.log",
        "target-setup": "/var/log/strawwu/target-setup.log",
        "firstboot": "/var/log/strawwu/firstboot.log",
        "app-registry": "/var/log/strawwu/app-registry.log",
        "update": "/var/log/strawwu/update.log",
        "wincompat": "/var/log/strawwu/wincompat.log",
    },
    "error_codes": [
        "SWU-BT-001", "SWU-IN-001", "SWU-IN-002", "SWU-FB-001",
        "SWU-FB-003", "SWU-AR-004", "SWU-UP-005", "SWU-WC-006",
        "SWU-FP-007", "SWU-RE-008",
    ],
    "bug_bundle": {
        "format": "bundle.strawwu-bug",
        "auto_upload_default": False,
        "consent_required": True,
        "schema_ready": True,
    },
    "wave0_gaps": [
        "structured JSON logging not wired",
    ],
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
pass "obs-baseline.json updated (schema_ready=true)"
validate_json_file "${BASELINES_DIR}/obs-baseline.json"

MARKER="${REPO_ROOT}/os-image/work/.bug-reporter-ok"
if [[ -f "${MARKER}" ]]; then
    pass "bug-reporter chroot marker present"
else
    warn "bug-reporter marker missing — run: sudo bash os-image/scripts/chroot-install-bug-reporter.sh"
fi

check_installed() {
    local label="$1"
    if package_installed_in_filesystem strawwu-bug-reporter; then
        pass "${label} strawwu-bug-reporter installed"
    else
        fail "${label} strawwu-bug-reporter missing"
    fi
}

check_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu-bug-report" ]]; then
        pass "${label} /usr/bin/strawwu-bug-report present"
    else
        fail "${label} /usr/bin/strawwu-bug-report missing"
    fi
    if [[ -x "${root}/usr/bin/strawwu-bug-report-gtk" ]]; then
        pass "${label} /usr/bin/strawwu-bug-report-gtk present"
    else
        fail "${label} /usr/bin/strawwu-bug-report-gtk missing"
    fi
}

check_log_dir() {
    local root="$1"
    local label="$2"
    if [[ -d "${root}/var/log/strawwu" ]]; then
        pass "${label} /var/log/strawwu present"
    else
        fail "${label} /var/log/strawwu missing"
    fi
}

check_apport_absent() {
    local label="$1"
    for pkg in apport apport-gtk python3-apport; do
        if package_installed_in_filesystem "${pkg}"; then
            fail "${label} ${pkg} still installed (should be purged)"
        fi
    done
    pass "${label} apport packages absent"
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        check_log_dir "${ROOTFS}" "rootfs"
        check_apport_absent "rootfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "rootfs"
        fi
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        check_log_dir "${SQUASHFS_ROOT}" "squashfs"
        check_apport_absent "squashfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "squashfs"
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W2-B2 bug-reporter"
