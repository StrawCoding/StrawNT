#!/usr/bin/env bash
# Shared helpers for StrawWU preflight scripts.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
SQUASHFS_ROOT="${REPO_ROOT}/os-image/work/squashfs-root"
ROOTFS="${REPO_ROOT}/os-image/work/rootfs"
BASELINES_DIR="${REPO_ROOT}/docs/plans/baselines"
PLANS_DIR="${REPO_ROOT}/docs/plans"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"

PREFLIGHT_FAIL=0

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*"
    PREFLIGHT_FAIL=1
}

warn() {
    echo "WARN: $*"
}

require_file() {
    local path="$1"
    local label="${2:-$1}"
    if [[ -f "${path}" ]]; then
        pass "${label}"
    else
        fail "${label} (missing ${path})"
    fi
}

require_plan() {
    local plan="$1"
    require_file "${PLANS_DIR}/${plan}" "plan ${plan}"
}

has_squashfs() {
    [[ -f "${SQUASHFS_ROOT}/var/lib/dpkg/status" ]]
}

has_rootfs() {
    [[ -d "${ROOTFS}/etc" ]]
}

list_installed_packages() {
    local status_file="$1"
    awk '/^Package: / { pkg=$2 }
         /^Status: / && / ok installed/ { print pkg }' "${status_file}" | sort -u
}

list_squashfs_packages() {
    if has_squashfs; then
        list_installed_packages "${SQUASHFS_ROOT}/var/lib/dpkg/status"
    fi
}

_dpkg_pkg_installed() {
    local pkg="$1"
    local list_fn="$2"
    local tmp
    tmp="$(mktemp)"
    "${list_fn}" > "${tmp}"
    grep -qxF "${pkg}" "${tmp}"
    local rc=$?
    rm -f "${tmp}"
    return "${rc}"
}

package_installed_in_squashfs() {
    local pkg="$1"
    has_squashfs || return 1
    _dpkg_pkg_installed "${pkg}" list_squashfs_packages
}

list_rootfs_packages() {
    if has_rootfs && [[ -f "${ROOTFS}/var/lib/dpkg/status" ]]; then
        list_installed_packages "${ROOTFS}/var/lib/dpkg/status"
    fi
}

package_installed_in_rootfs() {
    local pkg="$1"
    has_rootfs || return 1
    _dpkg_pkg_installed "${pkg}" list_rootfs_packages
}

package_installed_in_filesystem() {
    local pkg="$1"
    if package_installed_in_rootfs "${pkg}"; then
        return 0
    fi
    package_installed_in_squashfs "${pkg}"
}

# W1-B1 purge targets — must stay absent from rootfs/squashfs after purge.
PURGE_TARGET_PACKAGES=(
    apport
    apport-core-dump-handler
    whoopsie
    ubuntu-report
    ubuntu-pro-client
    ubuntu-pro-client-l10n
    ubuntu-advantage-desktop-daemon
    snapd
    snap-confine
)

count_squashfs_packages() {
    local pattern="${1:-.*}"
    if has_squashfs; then
        list_squashfs_packages | grep -E "${pattern}" | wc -l || true
    else
        echo 0
    fi
}

ensure_baselines_dir() {
    mkdir -p "${BASELINES_DIR}"
}

write_json_if_changed() {
    local target="$1"
    local content="$2"
    ensure_baselines_dir
    if [[ -f "${target}" ]] && cmp -s <(printf '%s\n' "${content}") "${target}"; then
        pass "baseline unchanged ${target}"
    else
        printf '%s\n' "${content}" > "${target}"
        pass "baseline written ${target}"
    fi
}

validate_json_file() {
    local path="$1"
    if python3 -m json.tool "${path}" >/dev/null 2>&1; then
        pass "valid JSON ${path}"
    else
        fail "invalid JSON ${path}"
    fi
}

preflight_exit() {
    local label="${1:-preflight}"
    if [[ "${PREFLIGHT_FAIL}" -eq 0 ]]; then
        echo "=== ${label} done: PASS ==="
        exit 0
    fi
    echo "=== ${label} done: FAIL ==="
    exit 1
}
