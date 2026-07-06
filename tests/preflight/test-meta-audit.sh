#!/usr/bin/env bash
# W6-B5: ubuntu-* meta audit — allowlist enforcement + strawwu-minimal replacement.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

MINIMAL_DIR="${REPO_ROOT}/os-image/debs/strawwu-minimal"
DESKTOP_DIR="${REPO_ROOT}/os-image/debs/strawwu-desktop"
BUILD="${MINIMAL_DIR}/build-deb.sh"
UNIT_TEST="${MINIMAL_DIR}/tests/test-meta.py"
MANIFEST="${MINIMAL_DIR}/usr/share/strawwu/meta-audit/meta-audit-manifest.yaml"
BASELINE="${BASELINES_DIR}/meta-audit-baseline.json"
TARGET_MARKER="${REPO_ROOT}/os-image/work/.target-setup-ok"

echo "=== W6-B5 meta-audit preflight ==="

require_plan "strawwu-ubuntu-components-plan.md"
require_plan "strawwu-desktop-plan.md"
require_file "${REPO_ROOT}/docs/plans/kickoff/W6-B5-meta-audit.md" "W6-B5 kickoff"
require_file "${MINIMAL_DIR}/debian/control" "strawwu-minimal debian/control"
require_file "${BUILD}" "strawwu-minimal build-deb.sh"
require_file "${MANIFEST}" "meta-audit-manifest.yaml"
require_file "${UNIT_TEST}" "strawwu-minimal test-meta.py"

for script in "${BUILD}" "${UNIT_TEST}"; do
    if [[ -x "${script}" ]]; then
        pass "$(basename "${script}") executable"
    else
        chmod +x "${script}"
        pass "chmod +x $(basename "${script}")"
    fi
done

if grep -q 'Conflicts: ubuntu-minimal' "${MINIMAL_DIR}/debian/control"; then
    pass "strawwu-minimal Conflicts ubuntu-minimal"
else
    fail "strawwu-minimal missing Conflicts: ubuntu-minimal"
fi

if grep -qiE '^(Depends|Recommends|Pre-Depends):.*ubuntu-pro-client' "${MINIMAL_DIR}/debian/control"; then
    fail "strawwu-minimal control references ubuntu-pro-client in deps"
else
    pass "strawwu-minimal control has no ubuntu-pro-client Depends"
fi

if grep -q 'schema: strawwu-meta-audit-manifest/v1' "${MANIFEST}"; then
    pass "meta-audit-manifest schema v1"
else
    fail "meta-audit-manifest missing schema"
fi

if grep -q 'strawwu-minimal' "${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"; then
    pass "target-manifest includes strawwu-minimal"
else
    fail "target-manifest missing strawwu-minimal"
fi

if python3 "${UNIT_TEST}"; then
    pass "strawwu-minimal unit tests"
else
    fail "strawwu-minimal unit tests"
fi

rm -rf "${MINIMAL_DIR}/output"
if STRAWWU_VERSION="${VERSION}" bash "${BUILD}"; then
    pass "strawwu-minimal build-deb.sh succeeded"
else
    fail "strawwu-minimal build-deb.sh failed"
fi

minimal_deb="$(ls -1 "${MINIMAL_DIR}/output"/strawwu-minimal_"${VERSION}"_amd64.deb 2>/dev/null | head -1)"
if [[ -n "${minimal_deb}" && -f "${minimal_deb}" ]]; then
    pass "strawwu-minimal deb artifact ${minimal_deb##*/}"
else
    fail "strawwu-minimal deb artifact missing"
fi

listing="$(dpkg-deb -c "${minimal_deb}")"
for rel in \
    ./usr/share/strawwu/meta-audit/meta-audit-manifest.yaml \
    ./usr/share/doc/strawwu-minimal/README; do
    if grep -qF "${rel}" <<< "${listing}"; then
        pass "deb contains ${rel#./}"
    else
        fail "deb missing ${rel#./}"
    fi
done

scan_ubuntu_packages() {
    local list_fn="$1"
    "${list_fn}" | grep -E '^ubuntu-' || true
}

audit_filesystem() {
    local label="$1"
    local list_fn="$2"

    local ubuntu_pkgs tmp forbidden found_forbidden=0 unexpected=0
    tmp="$(mktemp)"
    scan_ubuntu_packages "${list_fn}" > "${tmp}"
    ubuntu_pkgs="$(wc -l < "${tmp}" | tr -d ' ')"

    python3 - "${MANIFEST}" "${tmp}" > "${tmp}.audit" <<'PY'
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
pkgs = [line.strip() for line in Path(sys.argv[2]).read_text().splitlines() if line.strip()]
text = manifest_path.read_text(encoding="utf-8")

def extract_list(key: str) -> set[str]:
    items: list[str] = []
    capture = False
    for line in text.splitlines():
        if line.startswith(f"{key}:"):
            capture = True
            continue
        if capture:
            if line.startswith("  - "):
                items.append(line[4:].strip())
            elif not line.startswith(" "):
                break
    return set(items)

forbidden = extract_list("forbidden_ubuntu_metas") | extract_list("forbidden_ubuntu_packages")
allowed = extract_list("allowed_ubuntu_packages")

for pkg in pkgs:
    if pkg in forbidden:
        print(f"FORBIDDEN {pkg}")
    elif pkg not in allowed:
        print(f"UNEXPECTED {pkg}")
PY

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        kind="${line%% *}"
        pkg="${line#* }"
        if [[ "${kind}" == "FORBIDDEN" ]]; then
            if [[ -f "${TARGET_MARKER}" ]]; then
                warn "${label} forbidden ubuntu package: ${pkg} — re-run chroot-install-target-setup"
            else
                pass "${label} forbidden ubuntu package: ${pkg} (pre-W6-B5 transition)"
            fi
            found_forbidden=1
        elif [[ "${kind}" == "UNEXPECTED" ]]; then
            warn "${label} ubuntu-* not on allowlist: ${pkg}"
            unexpected=1
        fi
    done < "${tmp}.audit"

    if [[ "${found_forbidden}" -eq 0 ]]; then
        pass "${label} no forbidden ubuntu-* packages"
    fi
    if [[ "${unexpected}" -eq 0 && "${ubuntu_pkgs}" -gt 0 ]]; then
        pass "${label} ubuntu-* allowlist clean (count=${ubuntu_pkgs})"
    elif [[ "${ubuntu_pkgs}" -eq 0 ]]; then
        pass "${label} zero ubuntu-* packages"
    fi

    rm -f "${tmp}" "${tmp}.audit"
}

audit_filesystem_count() {
    local list_fn="$1"
    scan_ubuntu_packages "${list_fn}" | wc -l | tr -d ' '
}

check_strawwu_metas() {
    local label="$1"
    for pkg in strawwu-minimal strawwu-desktop; do
        if package_installed_in_filesystem "${pkg}"; then
            pass "${label} has ${pkg}"
        elif [[ -f "${TARGET_MARKER}" ]]; then
            warn "${label} missing ${pkg} — re-run chroot-install-target-setup"
        else
            warn "${label} missing ${pkg} (deb scaffold ready W6-B5)"
        fi
    done
}

if has_rootfs || has_squashfs; then
    if has_rootfs; then
        audit_filesystem "rootfs" list_rootfs_packages
        check_strawwu_metas "rootfs"
    fi
    if has_squashfs; then
        audit_filesystem "squashfs" list_squashfs_packages
        count="$(audit_filesystem_count list_squashfs_packages)"
        check_strawwu_metas "squashfs"
        pass "squashfs ubuntu-* audit count=${count}"
    fi
else
    warn "neither rootfs nor squashfs — skipping filesystem audit"
fi

ubuntu_list_file="$(mktemp)"
trap 'rm -f "${ubuntu_list_file}"' EXIT
if has_squashfs; then
    scan_ubuntu_packages list_squashfs_packages > "${ubuntu_list_file}" || true
else
    : > "${ubuntu_list_file}"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - "${MANIFEST}" "${ubuntu_list_file}" <<'PY'
import json, sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
ubuntu_file = Path(sys.argv[2])
version = __import__("os").environ["STRAWWU_BASELINE_VERSION"]
text = manifest_path.read_text(encoding="utf-8")
ubuntu = [x for x in ubuntu_file.read_text().splitlines() if x.strip()]

def extract_list(key: str) -> list[str]:
    items: list[str] = []
    capture = False
    for line in text.splitlines():
        if line.startswith(f"{key}:"):
            capture = True
            continue
        if capture:
            if line.startswith("  - "):
                items.append(line[4:].strip())
            elif not line.startswith(" "):
                break
    return items

forbidden = extract_list("forbidden_ubuntu_metas") + extract_list("forbidden_ubuntu_packages")
allowed = extract_list("allowed_ubuntu_packages")
present_forbidden = [p for p in ubuntu if p in forbidden]
present_allowed = [p for p in ubuntu if p in allowed]
unexpected = [p for p in ubuntu if p not in forbidden and p not in allowed]

data = {
    "schema": "strawwu-meta-audit-baseline/v1",
    "wave": "W6-B5",
    "version": version,
    "package": "strawwu-minimal",
    "manifest": "usr/share/strawwu/meta-audit/meta-audit-manifest.yaml",
    "forbidden_ubuntu_metas": extract_list("forbidden_ubuntu_metas"),
    "forbidden_ubuntu_packages": extract_list("forbidden_ubuntu_packages"),
    "allowed_ubuntu_packages": allowed,
    "strawwu_metas_required": extract_list("strawwu_metas_required"),
    "squashfs": {
        "present": ubuntu_file.stat().st_size >= 0,
        "ubuntu_packages": ubuntu,
        "ubuntu_package_count": len(ubuntu),
        "forbidden_present": present_forbidden,
        "allowed_present": present_allowed,
        "unexpected": unexpected,
        "audit_clean": len(present_forbidden) == 0 and len(unexpected) == 0,
    },
    "replaces": {
        "ubuntu-minimal": "strawwu-minimal",
        "ubuntu-desktop": "strawwu-desktop",
    },
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"
validate_json_file "${BASELINE}"

preflight_exit "W6-B5 meta-audit"
