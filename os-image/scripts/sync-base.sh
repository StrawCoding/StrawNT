#!/usr/bin/env bash
# sync-base.sh — Dispatch rootfs base sync by STRAWWU_BASE_MODE (clone | fork).
#
# Default mode comes from docs/plans/ubuntu-base-target.json → base_mode.
# Override: STRAWWU_BASE_MODE=clone|fork
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/ubuntu-base-env.sh
source "${SCRIPT_DIR}/lib/ubuntu-base-env.sh"
load_ubuntu_base_env "${REPO_ROOT}"

die() { echo "ERROR: $*" >&2; exit 1; }

mode="${STRAWWU_BASE_MODE:-clone}"
case "${mode}" in
    fork)
        exec bash "${SCRIPT_DIR}/fork-sync-base.sh" "$@"
        ;;
    clone)
        exec bash "${SCRIPT_DIR}/clone-ubuntu-base.sh" "$@"
        ;;
    *)
        die "unknown STRAWWU_BASE_MODE=${mode} (expected clone or fork)"
        ;;
esac
