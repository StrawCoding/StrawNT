#!/usr/bin/env bash
# fork-baseline-snapshot.sh — Capture validated rootfs as fork baseline snapshot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/ubuntu-base-env.sh
source "${SCRIPT_DIR}/lib/ubuntu-base-env.sh"
load_ubuntu_base_env "${REPO_ROOT}"

WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
FORK_BASE="${REPO_ROOT}/os-image/fork-base"
SNAP_DIR="${FORK_BASE}/snapshots"
MANIFEST="${FORK_BASE}/manifest.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root"
}

main() {
    need_root
    command -v tar zstd sha256sum python3 >/dev/null 2>&1 || die "need tar zstd sha256sum python3"

    [[ -d "${ROOTFS_DIR}/etc" ]] || die "rootfs missing — run clone-ubuntu-base or fork-sync-base first"
    [[ -f "${WORK_DIR}/.clone-ubuntu-base-ok" || -f "${WORK_DIR}/.fork-sync-base-ok" ]] \
        || die "no base marker — clone or fork-sync required"

    mkdir -p "${SNAP_DIR}"
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    local snap_name="fork-baseline-${VERSION}-${ts}.tar.zst"
    local snap_path="${SNAP_DIR}/${snap_name}"

    log "creating fork baseline snapshot: ${snap_path}"
    tar --xattrs --xattrs-include='*' -C "${ROOTFS_DIR}" -cf - . \
        | zstd -T0 -19 -o "${snap_path}"

    local sha size
    sha="$(sha256sum "${snap_path}" | awk '{print $1}')"
    size="$(stat -c '%s' "${snap_path}")"

    python3 - "${MANIFEST}" "${snap_name}" "${sha}" "${size}" "${VERSION}" \
        "${STRAWWU_UBUNTU_VERSION}" "${STRAWWU_APT_SUITE}" <<'PY'
import json, pathlib, sys, datetime
manifest, snap, sha, size, ver, ubuntu_ver, codename = sys.argv[1:8]
p = pathlib.Path(manifest)
data = json.loads(p.read_text()) if p.exists() else {}
data["schema"] = "strawwu-fork-base/v1"
data["status"] = "snapshot"
data["created_at"] = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
data.setdefault("ubuntu", {})
data["ubuntu"]["version"] = ubuntu_ver
data["ubuntu"]["codename"] = codename
data["snapshot"] = {
    "file": f"snapshots/{snap}",
    "sha256": sha,
    "size_bytes": int(size),
    "strawwu_version": ver,
}
p.write_text(json.dumps(data, indent=2) + "\n")
print(f"PASS: snapshot {snap} sha256={sha[:16]}…")
PY

    echo "${snap_path}" > "${WORK_DIR}/.fork-baseline-snapshot-path"
    date -Is > "${WORK_DIR}/.fork-baseline-snapshot-ok"
    log "fork baseline snapshot OK: ${snap_path} (${size} bytes)"
}

main "$@"
