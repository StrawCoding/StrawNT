#!/usr/bin/env bash
# ntw4-interop.sh — NTW4 Win32 IPC same_prefix + cross_prefix smoke evidence.
# Honesty: ranked_pass_claimed must be false; simulated must not be top-level PASS basis.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw4-interop.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/strawnt-ntw4.XXXXXX")"
export STRAWNT_HOME="${WORK}/home"
export STRAWNT_ROOT="${REPO_ROOT}"
export STRAWNT_FORCE_XVFB=1
mkdir -p "${OUT_DIR}" "${STRAWNT_HOME}"

cleanup() {
  if [[ -d "${STRAWNT_HOME}" ]]; then
    find "${STRAWNT_HOME}" -type d -name 'drive_c' -printf '%h\n' 2>/dev/null | while read -r p; do
      WINEPREFIX="${p}" \
        "${REPO_ROOT}/third_party/proton-ge/dist/files/bin/wineserver" -k 2>/dev/null || true
    done
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
command -v x86_64-w64-mingw32-gcc >/dev/null || {
  echo "x86_64-w64-mingw32-gcc required for PE fixtures" >&2
  exit 1
}

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
GIT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "== build fixtures =="
make -C "${REPO_ROOT}/components/strawnt-interop/fixtures" -j2

echo "== build strawwu-launcher + strawnt-interop =="
(cd "${REPO_ROOT}/components" && cargo build -p strawwu-launcher -p strawnt-interop -q)
STRAWNT_BIN="${REPO_ROOT}/components/target/debug/strawnt"
[[ -x "${STRAWNT_BIN}" ]] || { echo "strawnt binary missing" >&2; exit 1; }

SPEC="${REPO_ROOT}/docs/specs/interop-win32-ipc.md"
[[ -f "${SPEC}" ]] || { echo "missing ${SPEC}" >&2; exit 1; }

echo "== strawnt interop smoke --json =="
RAW="${WORK}/interop-raw.json"
"${STRAWNT_BIN}" interop smoke --json --home "${STRAWNT_HOME}" | tee "${RAW}"

python3 - <<'PY' "${RAW}" "${OUT_JSON}" "${VERSION}" "${TS}" "${GIT_HEAD}" "${SPEC}"
import json, sys
from pathlib import Path

raw_path, out_path, version, ts, git_head, spec = sys.argv[1:7]
raw = json.loads(Path(raw_path).read_text())
raw["version"] = version
raw["generated_at"] = ts
raw["git_head"] = git_head
raw["artifacts"] = {
    "spec": "docs/specs/interop-win32-ipc.md",
    "harness": "tests/strawnt/ntw4-interop.sh",
    "crate": "components/strawnt-interop",
    "daemon": "strawnt-interopd",
    "fixtures": "components/strawnt-interop/fixtures",
}
claims = raw.setdefault("claims", {})
claims["ranked_pass_claimed"] = False
claims.setdefault("same_prefix", bool(raw.get("same_prefix")))
claims.setdefault("cross_prefix", bool(raw.get("cross_prefix")))
# Top-level mirrors for Hermes jq gates
raw["same_prefix"] = bool(raw.get("same_prefix") or claims.get("same_prefix"))
raw["cross_prefix"] = bool(raw.get("cross_prefix") or claims.get("cross_prefix"))
if raw.get("simulated") is True and raw.get("status") == "PASS":
    raw["status"] = "FAIL"
    raw.setdefault("notes", []).append("refusing simulated top-level PASS")
Path(out_path).write_text(json.dumps(raw, indent=2, sort_keys=False) + "\n")
print(f"wrote {out_path} status={raw.get('status')}")
PY

echo "== hermes gate checks =="
jq -e '.status == "PASS"' "${OUT_JSON}" >/dev/null
jq -e '(.same_prefix == true or .claims.same_prefix == true)' "${OUT_JSON}" >/dev/null
jq -e '(.cross_prefix == true or .claims.cross_prefix == true)' "${OUT_JSON}" >/dev/null
jq -e '(.claims.ranked_pass_claimed // false) == false' "${OUT_JSON}" >/dev/null
test -f "${SPEC}"
test -f "${OUT_JSON}"

echo "NTW4 interop evidence PASS → ${OUT_JSON}"
