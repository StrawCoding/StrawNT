#!/usr/bin/env bash
# ntw5-appmgr.sh — NTW5 system App Manager evidence.
# Honesty: top-level PASS requires real PE-staged install + Wine PE launch via App Manager —
# never registration-only INSTALLED.json / cmd_marker / simulated.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw5-appmgr.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/strawnt-ntw5.XXXXXX")"
export STRAWNT_HOME="${WORK}/home"
export STRAWNT_ROOT="${REPO_ROOT}"
export STRAWNT_FORCE_XVFB=1
export STRAWWU_APP_REGISTRY="${WORK}/app-registry.json"
mkdir -p "${OUT_DIR}" "${STRAWNT_HOME}"
printf '%s\n' '{"schema_version":"1.0","apps":[]}' > "${STRAWWU_APP_REGISTRY}"

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
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "x86_64-w64-mingw32-gcc required for PE fixture" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
GIT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

require_file() {
  local rel="$1"
  if [[ ! -f "${REPO_ROOT}/${rel}" ]]; then
    echo "missing ${rel}" >&2
    exit 1
  fi
}

require_file "components/strawnt-appmgr/src/lib.rs"
require_file "components/strawnt-appmgr/catalog/local-catalog.json"
require_file "components/strawnt-appmgr/fixtures/strawnt_app_stub.c"
require_file "docs/schemas/app-manifest.schema.json"
require_file "hub/resources/desktop/strawnt-app-manager.desktop"
require_file "third_party/proton-ge/PIN"

echo "== build appmgr PE fixture =="
make -C "${REPO_ROOT}/components/strawnt-appmgr/fixtures" -j2
FIXTURE_PE="${REPO_ROOT}/components/strawnt-appmgr/fixtures/build/strawnt_app_stub.exe"
[[ -f "${FIXTURE_PE}" ]] || { echo "fixture PE missing" >&2; exit 1; }

echo "== build strawwu-launcher + strawnt-appmgr =="
(cd "${REPO_ROOT}/components" && cargo build -p strawwu-launcher -p strawnt-appmgr -q)
STRAWNT_BIN="${REPO_ROOT}/components/target/debug/strawnt"
[[ -x "${STRAWNT_BIN}" ]] || { echo "strawnt binary missing" >&2; exit 1; }

load_pin() {
  local pin_file="$1"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    if [[ "${line}" =~ ^([a-z_][a-z0-9_]*)=(.*)$ ]]; then
      printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
    fi
  done < "${pin_file}"
}
load_pin "${REPO_ROOT}/third_party/proton-ge/PIN"
PIN_TAG="${tag:-}"
[[ -n "${PIN_TAG}" ]] || { echo "PIN tag empty" >&2; exit 1; }

echo "== strawnt apps smoke --json =="
RAW="${WORK}/appmgr-raw.json"
"${STRAWNT_BIN}" apps smoke --json --home "${STRAWNT_HOME}" | tee "${RAW}"

# Hub App Manager entry checks (Electron hub locked — not Vue).
HUB_HTML="${REPO_ROOT}/hub/src/renderer/index.html"
HUB_JS="${REPO_ROOT}/hub/src/renderer/renderer.js"
HUB_EN="${REPO_ROOT}/hub/locales/en.json"
HUB_DESKTOP="${REPO_ROOT}/hub/resources/desktop/strawnt-app-manager.desktop"
HUB_OK=true
grep -q 'data-tab="apps"' "${HUB_HTML}" || HUB_OK=false
grep -q 'App Manager\|app.manager\|apps.title' "${HUB_EN}" || HUB_OK=false
grep -q 'btn-refresh-apps\|apps-list' "${HUB_JS}" || HUB_OK=false
[[ -f "${HUB_DESKTOP}" ]] || HUB_OK=false
grep -qi 'App Manager' "${HUB_DESKTOP}" || HUB_OK=false
grep -qi 'powered by Wine' "${HUB_DESKTOP}" || HUB_OK=false

SCHEMA_OK=false
[[ -f "${REPO_ROOT}/docs/schemas/app-manifest.schema.json" ]] && SCHEMA_OK=true

python3 - <<'PY' "${RAW}" "${OUT_JSON}" "${VERSION}" "${TS}" "${GIT_HEAD}" "${PIN_TAG}" "${HUB_OK}" "${SCHEMA_OK}" "${FIXTURE_PE}"
import json, sys
from pathlib import Path

raw_path, out_path, version, ts, git_head, pin, hub_ok, schema_ok, fixture_pe = sys.argv[1:10]
raw = json.loads(Path(raw_path).read_text())
raw["version"] = version
raw["generated_at"] = ts
raw["git_head"] = git_head
raw["pin"] = pin
raw["engine_pin"] = pin
raw["hub"] = "electron"
raw["hub_app_manager_entry"] = hub_ok.lower() in ("true", "1", "yes")
raw["schema_present"] = schema_ok.lower() in ("true", "1", "yes")
raw["fixture_pe"] = fixture_pe
raw["artifacts"] = {
    "crate": "components/strawnt-appmgr",
    "catalog": "components/strawnt-appmgr/catalog/local-catalog.json",
    "fixture": "components/strawnt-appmgr/fixtures",
    "schema": "docs/schemas/app-manifest.schema.json",
    "harness": "tests/strawnt/ntw5-appmgr.sh",
    "hub_desktop": "hub/resources/desktop/strawnt-app-manager.desktop",
    "hub": "hub/",
}
claims = raw.setdefault("claims", {})
caps = raw.setdefault("capabilities", {})
claims.setdefault("install", bool(caps.get("install")))
claims.setdefault("list_launch", bool(caps.get("list_launch")))
claims.setdefault("prefix", bool(caps.get("prefix")))
claims["powered_by_wine"] = True
claims["full_windows_claimed"] = False
claims["ranked_anticheat_claimed"] = False
claims["simulated"] = False
# Top-level mirrors for Hermes jq gates
raw["install"] = bool(caps.get("install") or claims.get("install"))
raw["list_launch"] = bool(caps.get("list_launch") or claims.get("list_launch"))
raw["prefix"] = bool(caps.get("prefix") or claims.get("prefix"))

results = raw.get("results") or {}
install_line = results.get("install_line") or {}
launch = results.get("launch") or {}
notes = raw.setdefault("notes", [])
failures = raw.setdefault("failures", [])

def fail(msg: str) -> None:
    failures.append(msg)
    notes.append(msg)
    raw["status"] = "FAIL"

if install_line.get("install_mode") != "pe_staged":
    fail(f"install_line.install_mode={install_line.get('install_mode')!r} (require pe_staged)")
if launch.get("mode") != "pe":
    fail(f"launch.mode={launch.get('mode')!r} (require pe — refuse cmd_marker)")
if (launch.get("honesty") or {}).get("simulated") is True:
    fail("launch honesty.simulated=true refused")
if raw.get("simulated") is True:
    fail("top-level simulated=true refused")

if not raw.get("hub_app_manager_entry"):
    fail("Hub App Manager entry missing")
if not raw.get("schema_present"):
    fail("app-manifest schema missing")
if raw.get("simulated") is True and raw.get("status") == "PASS":
    fail("refusing simulated top-level PASS")

Path(out_path).write_text(json.dumps(raw, indent=2, sort_keys=False) + "\n")
print(f"wrote {out_path} status={raw.get('status')}")
PY

echo "== hermes gate checks =="
jq -e '.status == "PASS"' "${OUT_JSON}" >/dev/null
jq -e '(.capabilities.install == true) or (.claims.install == true)' "${OUT_JSON}" >/dev/null
jq -e '(.capabilities.list_launch == true) or (.claims.list_launch == true)' "${OUT_JSON}" >/dev/null
jq -e '(.capabilities.prefix == true) or (.claims.prefix == true)' "${OUT_JSON}" >/dev/null
jq -e '.results.install_line.install_mode == "pe_staged"' "${OUT_JSON}" >/dev/null
jq -e '.results.launch.mode == "pe"' "${OUT_JSON}" >/dev/null
jq -e '.results.launch.honesty.simulated != true' "${OUT_JSON}" >/dev/null
test -f "${OUT_JSON}"

echo "NTW5 App Manager evidence PASS → ${OUT_JSON}"
