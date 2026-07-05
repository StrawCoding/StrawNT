#!/usr/bin/env bash
# W3-W0: strawwu-wincompat — rootfs baseline for strawwu CLI + status.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

DEB_DIR="${REPO_ROOT}/os-image/debs/strawwu-wincompat"
BUILD="${DEB_DIR}/build-deb.sh"
CHROOT="${REPO_ROOT}/os-image/scripts/chroot-install-wincompat.sh"
UNIT_TEST="${DEB_DIR}/tests/test-wincompat-cli.sh"
OUTPUT_DIR="${DEB_DIR}/output"
BASELINE="${BASELINES_DIR}/wincompat-os-baseline.json"
BASELINE_YAML="${DEB_DIR}/usr/share/strawwu/wincompat/baseline.yaml"

echo "=== W3-W0 wincompat-os preflight ==="

require_plan "strawwu-windows-compat-integration-plan.md"
require_plan "strawwu-observability-debug-plan.md"

require_file "${REPO_ROOT}/components/Cargo.toml" "components workspace"
require_file "${REPO_ROOT}/Makefile" "Makefile test-wincompat target"
require_file "${DEB_DIR}/debian/control" "strawwu-wincompat debian/control"
require_file "${DEB_DIR}/debian/postinst" "strawwu-wincompat debian/postinst"
require_file "${BUILD}" "strawwu-wincompat build-deb.sh"
require_file "${CHROOT}" "chroot-install-wincompat.sh"
require_file "${BASELINE_YAML}" "wincompat baseline.yaml"
require_file "${UNIT_TEST}" "wincompat CLI unit test"

if grep -q '^test-wincompat:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-wincompat"
else
    fail "Makefile missing test-wincompat"
fi

expected_crates=(strawwu-launcher strawwu-runtime strawwu-nt strawwu-bridge)
for crate in "${expected_crates[@]}"; do
    if [[ -d "${REPO_ROOT}/components/${crate}" ]]; then
        pass "crate ${crate}"
    else
        fail "missing crate ${crate}"
    fi
done

if grep -q 'strawwu-wincompat-baseline/v1' "${BASELINE_YAML}"; then
    pass "baseline.yaml schema v1"
else
    fail "baseline.yaml missing schema"
fi

if grep -q '/var/log/strawwu/wincompat.log' "${BASELINE_YAML}"; then
    pass "baseline.yaml log path"
else
    fail "baseline.yaml missing log path"
fi

if grep -q '/var/log/strawwu/wincompat.log' "${PLANS_DIR}/strawwu-observability-debug-plan.md"; then
    pass "observability plan documents wincompat.log"
else
    fail "observability plan missing wincompat.log path"
fi

for script in "${BUILD}" "${CHROOT}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

rm -rf "${OUTPUT_DIR}"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "build-deb.sh succeeded"
else
    fail "build-deb.sh failed"
fi

deb_file="$(ls -1 "${OUTPUT_DIR}"/strawwu-wincompat_"${VERSION}"_amd64.deb 2>/dev/null | head -1)"
if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
    pass "deb artifact ${deb_file##*/}"
else
    fail "deb artifact missing"
fi

listing="$(dpkg-deb -c "${deb_file}")"
for rel in \
    ./usr/bin/strawwu \
    ./usr/share/strawwu/wincompat/baseline.yaml; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
dpkg-deb -x "${deb_file}" "${tmpdir}"
chmod +x "${tmpdir}/usr/bin/strawwu"

if STRAWWU_BIN="${tmpdir}/usr/bin/strawwu" bash "${UNIT_TEST}"; then
    pass "wincompat CLI unit tests (unpacked deb)"
else
    fail "wincompat CLI unit tests"
fi

if "${tmpdir}/usr/bin/strawwu" status | grep -q 'status'; then
    pass "strawwu status on unpacked deb"
else
    fail "strawwu status output unexpected"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-wincompat-os-baseline/v1",
    "wave": "W3-W0",
    "version": version,
    "package": "strawwu-wincompat",
    "cli_path": "/usr/bin/strawwu",
    "log_path": "/var/log/strawwu/wincompat.log",
    "baseline_yaml": "usr/share/strawwu/wincompat/baseline.yaml",
    "commands_baseline": ["status", "version", "run", "install", "apps"],
    "execution_backend_default": "native",
    "dod": "strawwu status runnable on Live rootfs",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

MARKER="${REPO_ROOT}/os-image/work/.wincompat-ok"
if [[ -f "${MARKER}" ]]; then
    pass "wincompat chroot marker present"
else
    warn "wincompat marker missing — run: sudo bash os-image/scripts/chroot-install-wincompat.sh"
fi

check_installed() {
    local label="$1"
    if package_installed_in_filesystem strawwu-wincompat; then
        pass "${label} strawwu-wincompat installed"
    else
        fail "${label} strawwu-wincompat missing"
    fi
}

check_cli() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu" ]]; then
        pass "${label} /usr/bin/strawwu present"
    else
        fail "${label} /usr/bin/strawwu missing"
    fi
}

check_status() {
    local root="$1"
    local label="$2"
    if [[ -x "${root}/usr/bin/strawwu" ]]; then
        if chroot "${root}" /usr/bin/strawwu status 2>/dev/null | grep -q 'status'; then
            pass "${label} strawwu status runnable"
        elif "${root}/usr/bin/strawwu" status 2>/dev/null | grep -q 'status'; then
            pass "${label} strawwu status runnable (host exec)"
        else
            fail "${label} strawwu status failed"
        fi
    fi
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        check_cli "${ROOTFS}" "rootfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "rootfs"
            check_status "${ROOTFS}" "rootfs"
        fi
    fi
    if has_squashfs; then
        check_cli "${SQUASHFS_ROOT}" "squashfs"
        if [[ -f "${MARKER}" ]]; then
            check_installed "squashfs"
            if [[ -x "${SQUASHFS_ROOT}/usr/bin/strawwu" ]]; then
                if "${SQUASHFS_ROOT}/usr/bin/strawwu" status 2>/dev/null | grep -q 'status'; then
                    pass "squashfs strawwu status runnable"
                else
                    fail "squashfs strawwu status failed"
                fi
            fi
        else
            if [[ -x "${SQUASHFS_ROOT}/usr/bin/strawwu" ]]; then
                pass "squashfs has /usr/bin/strawwu"
            else
                warn "squashfs missing /usr/bin/strawwu (run chroot-install-wincompat.sh)"
            fi
        fi
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem install checks"
fi

preflight_exit "W3-W0 wincompat-os"
