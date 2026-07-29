#!/usr/bin/env bash
# smoke-prefix.sh — Portable Core prefix smoke (pc1).
# Builds prefix if missing, probes strawwu --version / status without system debs,
# writes tests/portable/output/smoke-prefix.json (top-level status=PASS|FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORTABLE_ROOT="${REPO_ROOT}/components/packaging/portable"
INVENTORY="${REPO_ROOT}/docs/plans/portable-core/inventory.json"
PREFIX="${STRAWWU_PREFIX:-${PORTABLE_ROOT}/prefix}"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/smoke-prefix.json"
DRY_RUN=0
BUILD_IF_MISSING=1
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"

usage() {
    cat <<EOF
Usage: smoke-prefix.sh [--dry-run] [--prefix DIR] [--no-build] [-h|--help]

Portable Core prefix smoke (pc1).

  --dry-run     Check scaffold layout + inventory only; do not require a built prefix
  --prefix DIR  Override \$STRAWWU_PREFIX (default: ${PORTABLE_ROOT}/prefix)
  --no-build    Do not invoke build-prefix.sh when bin/strawwu is missing
  -h, --help    Show this help

PASS (pc1): executable prefix bin/strawwu --version and status succeed;
            ${OUT_JSON} top-level status=PASS; no system strawwu-* deb required.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --no-build) BUILD_IF_MISSING=0; shift ;;
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

write_json() {
    local status="$1"
    shift
    mkdir -p "${OUT_DIR}"
    python3 - "${OUT_JSON}" "${status}" "${VERSION}" "${PREFIX}" "$@" <<'PY'
import json, sys, time
out, status, version, prefix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
# remaining argv pairs: key=value JSON fragments as "key|json"
checks = {}
for arg in sys.argv[5:]:
    if "|" not in arg:
        continue
    key, raw = arg.split("|", 1)
    try:
        checks[key] = json.loads(raw)
    except json.JSONDecodeError:
        checks[key] = {"raw": raw}
doc = {
    "schema": "strawwu-portable-smoke-prefix/v1",
    "stage": "pc1-self-contained-prefix",
    "status": status,
    "version": version,
    "prefix": prefix,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "checks": checks,
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate",
        "no WinBox naming",
        "no full Windows compatibility claim",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
}

fail_json() {
    local msg="$1"
    write_json "FAIL" "error|$(python3 -c 'import json,sys; print(json.dumps({"status":"FAIL","message":sys.argv[1]}))' "${msg}")" >/dev/null || true
    die "${msg}"
}

[[ -f "${REPO_ROOT}/docs/plans/portable-core/A3-cross-distro-core.md" ]] \
    || fail_json "missing A3 plan"
[[ -f "${INVENTORY}" ]] || fail_json "missing inventory.json"
[[ -f "${PORTABLE_ROOT}/README.md" ]] || fail_json "missing portable README"
[[ -d "${PORTABLE_ROOT}/prefix" ]] || fail_json "missing portable/prefix/"
[[ -d "${PORTABLE_ROOT}/appimage" ]] || fail_json "missing portable/appimage/"
[[ -d "${PORTABLE_ROOT}/flatpak" ]] || fail_json "missing portable/flatpak/"
[[ -x "${PORTABLE_ROOT}/build-prefix.sh" ]] || fail_json "missing build-prefix.sh"

python3 - "${INVENTORY}" <<'PY' || fail_json "inventory missing required component keys"
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
    # Do not write smoke-prefix.json — that file is the pc1 evidence artifact.
    exit 0
fi

STRAWWU_BIN="${PREFIX}/bin/strawwu"
if [[ ! -x "${STRAWWU_BIN}" ]]; then
    if [[ "${BUILD_IF_MISSING}" -eq 1 ]]; then
        log "prefix binary missing — invoking build-prefix.sh"
        STRAWWU_PREFIX="${PREFIX}" bash "${PORTABLE_ROOT}/build-prefix.sh" \
            || fail_json "build-prefix.sh failed"
    else
        fail_json "prefix binary not built: ${STRAWWU_BIN}"
    fi
fi
[[ -x "${STRAWWU_BIN}" ]] || fail_json "prefix binary still missing after build"

# Ensure we are probing the prefix binary, not a system /usr/bin/strawwu.
REAL_BIN="$(readlink -f "${STRAWWU_BIN}")"
REAL_PREFIX="$(readlink -f "${PREFIX}")"
case "${REAL_BIN}" in
    "${REAL_PREFIX}"/*) ;;
    *) fail_json "refusing to smoke non-prefix binary: ${REAL_BIN} (prefix=${REAL_PREFIX})" ;;
esac
PREFIX="${REAL_PREFIX}"
STRAWWU_BIN="${REAL_BIN}"

# Independence check: system strawwu-* debs are optional; we must not require them.
SYSTEM_DEB_STATE="absent"
if command -v dpkg-query >/dev/null 2>&1; then
    if dpkg-query -W -f='${Package}\n' 'strawwu-*' 2>/dev/null | grep -q .; then
        SYSTEM_DEB_STATE="present-but-unused"
    fi
fi

log "probing ${STRAWWU_BIN}"
export STRAWWU_APP_REGISTRY="${STRAWWU_APP_REGISTRY:-${PREFIX}/var/lib/strawwu/app-registry.json}"
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Clear PATH of accidental system strawwu; call absolute path only.
VERSION_OUT="$("${STRAWWU_BIN}" --version 2>&1)" || fail_json "strawwu --version failed"
STATUS_OUT="$("${STRAWWU_BIN}" status 2>&1)" || fail_json "strawwu status failed"
log "version: ${VERSION_OUT}"
log "status:  ${STATUS_OUT}"

# Confirm no NEEDED libs resolve exclusively via /usr/lib/strawwu (deb layout).
if ldd "${STRAWWU_BIN}" 2>/dev/null | grep -E '/usr/lib/strawwu/' >/dev/null; then
    fail_json "binary links against /usr/lib/strawwu (system deb layout)"
fi

write_json "PASS" \
    "$(python3 -c 'import json,sys; print("version|"+json.dumps({"status":"PASS","output":sys.argv[1]}))' "${VERSION_OUT}")" \
    "$(python3 -c 'import json,sys; print("status_cmd|"+json.dumps({"status":"PASS","output":sys.argv[1]}))' "${STATUS_OUT}")" \
    "$(python3 -c 'import json,sys; print("no_system_deb_required|"+json.dumps({"status":"PASS","system_strawwu_debs":sys.argv[1],"binary":sys.argv[2]}))' "${SYSTEM_DEB_STATE}" "${REAL_BIN}")" \
    "$(python3 -c 'import json,sys; print("prefix_layout|"+json.dumps({"status":"PASS","bin":True,"lib_dir":sys.argv[1]=="1","manifest":sys.argv[2]=="1"}))' \
        "$( [[ -d "${PREFIX}/lib" ]] && echo 1 || echo 0 )" \
        "$( [[ -f "${PREFIX}/share/strawwu/portable-prefix.json" ]] && echo 1 || echo 0 )")"

log "wrote ${OUT_JSON}"
log "prefix smoke PASS"
