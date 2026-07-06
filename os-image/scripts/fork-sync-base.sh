#!/usr/bin/env bash
# fork-sync-base.sh — Restore fork rootfs from snapshot or seed from clone + manifest.
#
# Modes:
#   STRAWWU_FORK_SYNC=restore  — restore from fork-base/snapshots/ (default if snapshot exists)
#   STRAWWU_FORK_SYNC=seed     — clone from ISO then apply manifest (first-time seed)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/ubuntu-base-env.sh
source "${SCRIPT_DIR}/lib/ubuntu-base-env.sh"
load_ubuntu_base_env "${REPO_ROOT}"

WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
FORK_BASE="${REPO_ROOT}/os-image/fork-base"
MANIFEST="${FORK_BASE}/manifest.json"
MARKER="${WORK_DIR}/.fork-sync-base-ok"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root"
}

resolve_snapshot() {
    python3 - "${MANIFEST}" "${FORK_BASE}" <<'PY'
import json, pathlib, sys
manifest, fork_base = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
if not manifest.exists():
    raise SystemExit(1)
data = json.loads(manifest.read_text())
snap = data.get("snapshot", {}).get("file")
if not snap:
    raise SystemExit(1)
path = fork_base / snap
if path.is_file():
    print(path)
PY
}

restore_snapshot() {
    local snap="$1"
    log "restoring fork snapshot: ${snap}"
    rm -rf "${ROOTFS_DIR}"
    mkdir -p "${ROOTFS_DIR}"
    zstd -d -c "${snap}" | tar --xattrs --xattrs-include='*' -C "${ROOTFS_DIR}" -xf -
}

seed_from_clone() {
    log "seeding fork base from clone-ubuntu-base"
    bash "${SCRIPT_DIR}/clone-ubuntu-base.sh"
    bash "${SCRIPT_DIR}/fork-apply-manifest.sh"
}

main() {
    need_root
    command -v zstd tar python3 >/dev/null 2>&1 || die "need zstd tar python3"

    local mode="${STRAWWU_FORK_SYNC:-auto}"
    local snap=""

    if [[ "${mode}" == "auto" ]]; then
        if snap="$(resolve_snapshot 2>/dev/null || true)"; then
            mode="restore"
        else
            mode="seed"
        fi
    fi

    case "${mode}" in
        restore)
            snap="${snap:-$(resolve_snapshot || die "no snapshot in manifest")}"
            restore_snapshot "${snap}"
            ;;
        seed)
            seed_from_clone
            ;;
        *)
            die "unknown STRAWWU_FORK_SYNC=${mode}"
            ;;
    esac

    date -Is > "${MARKER}"
    log "fork-sync-base OK (mode=${mode})"
}

main "$@"
