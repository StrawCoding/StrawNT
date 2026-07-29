#!/usr/bin/env bash
# pc0 scaffold: portable prefix smoke entry stub.
# Full prefix execution (--version / status without system debs) is pc1.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORTABLE_ROOT="${REPO_ROOT}/components/packaging/portable"
INVENTORY="${REPO_ROOT}/docs/plans/portable-core/inventory.json"
PREFIX="${STRAWWU_PREFIX:-${PORTABLE_ROOT}/prefix}"
DRY_RUN=0

usage() {
    cat <<EOF
Usage: smoke-prefix.sh [--dry-run] [--prefix DIR] [-h|--help]

Portable Core prefix smoke entry (scaffold in pc0).

  --dry-run     Check scaffold layout + inventory only; do not require a built prefix
  --prefix DIR  Override \$STRAWWU_PREFIX (default: ${PORTABLE_ROOT}/prefix)
  -h, --help    Show this help

pc0 PASS: script is executable and --help / --dry-run succeed.
pc1+:    will probe \$STRAWWU_PREFIX/bin/strawwu --version and status.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "ERROR: unknown arg: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-prefix] $*"; }

[[ -f "${REPO_ROOT}/docs/plans/portable-core/A3-cross-distro-core.md" ]] \
    || die "missing A3 plan"
[[ -f "${INVENTORY}" ]] || die "missing inventory.json"
[[ -f "${PORTABLE_ROOT}/README.md" ]] || die "missing portable README"
[[ -d "${PORTABLE_ROOT}/prefix" ]] || die "missing portable/prefix/"
[[ -d "${PORTABLE_ROOT}/appimage" ]] || die "missing portable/appimage/"
[[ -d "${PORTABLE_ROOT}/flatpak" ]] || die "missing portable/flatpak/"

python3 - "${INVENTORY}" <<'PY' || die "inventory missing required component keys"
import json, sys
path = sys.argv[1]
data = json.load(open(path))
comps = data.get("components", data)
blob = json.dumps(comps).lower()
required = ["runtime", "nt", "launcher", "cli", "graphics", "audio", "hub"]
missing = [k for k in required if k not in blob]
if missing:
    print("missing keys:", ", ".join(missing), file=sys.stderr)
    sys.exit(1)
print("inventory OK:", ", ".join(required))
PY

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run PASS (scaffold + inventory)"
    log "prefix target (not required yet): ${PREFIX}"
    exit 0
fi

STRAWWU_BIN="${PREFIX}/bin/strawwu"
if [[ ! -x "${STRAWWU_BIN}" ]]; then
    log "prefix binary not built yet (expected at pc1): ${STRAWWU_BIN}"
    log "scaffold checks passed; use --dry-run for explicit pc0 gate"
    exit 0
fi

log "probing ${STRAWWU_BIN}"
"${STRAWWU_BIN}" --version
"${STRAWWU_BIN}" status
log "prefix smoke PASS"
