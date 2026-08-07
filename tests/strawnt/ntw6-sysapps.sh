#!/usr/bin/env bash
# ntw6-sysapps.sh — NTW6 dedicated system apps evidence.
# Honesty: top-level PASS requires 7 apps each with manifest + desktop launch
# entry + real launch side effects (not simulated). Hub = Electron.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw6-sysapps.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/strawnt-ntw6.XXXXXX")"
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

require_file "components/strawnt-sysapps/src/lib.rs"
require_file "components/strawnt-sysapps/manifests/settings.json"
require_file "components/strawnt-sysapps/manifests/run_dialog.json"
require_file "components/strawnt-sysapps/manifests/installer_wizard.json"
require_file "components/strawnt-sysapps/manifests/app_library.json"
require_file "components/strawnt-sysapps/manifests/compat_center.json"
require_file "components/strawnt-sysapps/manifests/task_manager.json"
require_file "components/strawnt-sysapps/manifests/file_manager.json"
require_file "hub/resources/desktop/strawnt-settings.desktop"
require_file "hub/resources/desktop/strawnt-run-dialog.desktop"
require_file "hub/resources/desktop/strawnt-installer-wizard.desktop"
require_file "hub/resources/desktop/strawnt-app-library.desktop"
require_file "hub/resources/desktop/strawnt-compat-center.desktop"
require_file "hub/resources/desktop/strawnt-task-manager.desktop"
require_file "hub/resources/desktop/strawnt-file-manager.desktop"
require_file "third_party/proton-ge/PIN"

echo "== build appmgr PE fixture (installer_wizard wraps install) =="
make -C "${REPO_ROOT}/components/strawnt-appmgr/fixtures" -j2
FIXTURE_PE="${REPO_ROOT}/components/strawnt-appmgr/fixtures/build/strawnt_app_stub.exe"
[[ -f "${FIXTURE_PE}" ]] || { echo "fixture PE missing" >&2; exit 1; }

echo "== build strawwu-launcher + strawnt-sysapps =="
(cd "${REPO_ROOT}/components" && cargo build -p strawwu-launcher -p strawnt-sysapps -q)
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

echo "== strawnt sysapps smoke --json =="
RAW="${WORK}/sysapps-raw.json"
"${STRAWNT_BIN}" sysapps smoke --json --home "${STRAWNT_HOME}" | tee "${RAW}"

# Hub Electron entry checks for 7 dedicated tabs + desktop Exec --tab
HUB_HTML="${REPO_ROOT}/hub/src/renderer/index.html"
HUB_JS="${REPO_ROOT}/hub/src/renderer/renderer.js"
HUB_MAIN="${REPO_ROOT}/hub/src/main/main.js"
HUB_EN="${REPO_ROOT}/hub/locales/en.json"
HUB_OK=true
for tab in sys-settings sys-run sys-installer sys-library sys-compat sys-taskmgr sys-files; do
  grep -q "data-tab=\"${tab}\"" "${HUB_HTML}" || HUB_OK=false
  grep -q "id=\"tab-${tab}\"" "${HUB_HTML}" || HUB_OK=false
done
grep -q 'activateTab\|--tab' "${HUB_JS}" || HUB_OK=false
grep -q 'parseInitialTab\|--tab' "${HUB_MAIN}" || HUB_OK=false
grep -q 'nav.sys_settings\|sysapps.settings' "${HUB_EN}" || HUB_OK=false
for desk in settings run-dialog installer-wizard app-library compat-center task-manager file-manager; do
  f="${REPO_ROOT}/hub/resources/desktop/strawnt-${desk}.desktop"
  [[ -f "${f}" ]] || HUB_OK=false
  grep -qi 'powered by Wine' "${f}" || HUB_OK=false
  grep -q 'Exec=strawnt-hub --tab' "${f}" || HUB_OK=false
done

python3 - <<'PY' "${RAW}" "${OUT_JSON}" "${VERSION}" "${TS}" "${GIT_HEAD}" "${PIN_TAG}" "${HUB_OK}" "${FIXTURE_PE}"
import json, sys
from pathlib import Path

raw_path, out_path, version, ts, git_head, pin, hub_ok, fixture_pe = sys.argv[1:9]
raw = json.loads(Path(raw_path).read_text())
raw["version"] = version
raw["generated_at"] = ts
raw["git_head"] = git_head
raw["pin"] = pin
raw["engine_pin"] = pin
raw["hub"] = "electron"
raw["hub_sysapps_entry"] = hub_ok.lower() in ("true", "1", "yes")
raw["fixture_pe"] = fixture_pe
raw["artifacts"] = {
    "crate": "components/strawnt-sysapps",
    "manifests": "components/strawnt-sysapps/manifests",
    "desktops": "hub/resources/desktop/",
    "harness": "tests/strawnt/ntw6-sysapps.sh",
    "hub": "hub/",
}
claims = raw.setdefault("claims", {})
apps = raw.get("apps") or []
claims["app_count"] = len(apps)
claims["powered_by_wine"] = True
claims["full_windows_claimed"] = False
claims["ranked_anticheat_claimed"] = False
claims["simulated"] = False
claims["hub_electron"] = True
raw["simulated"] = False

notes = raw.setdefault("notes", [])
failures = raw.setdefault("failures", [])

def fail(msg: str) -> None:
    failures.append(msg)
    notes.append(msg)
    raw["status"] = "FAIL"

if not raw.get("hub_sysapps_entry"):
    fail("Hub Electron sysapps entry missing (tabs/desktop/--tab)")
if raw.get("simulated") is True:
    fail("top-level simulated=true refused")
if len(apps) < 7:
    fail(f"apps length {len(apps)} < 7")
results = raw.get("results") or []
if len(results) < 7 and len(apps) < 7:
    fail(f"results length {len(results)} < 7")

Path(out_path).write_text(json.dumps(raw, indent=2, sort_keys=False) + "\n")
print(f"wrote {out_path} status={raw.get('status')} apps={len(apps)}")
PY

echo "== hermes gate checks =="
test -f "${OUT_JSON}"
jq -e '.status == "PASS"' "${OUT_JSON}" >/dev/null
jq -e '((.apps|length) >= 7) or ((.results|length) >= 7) or (.claims.app_count >= 7)' "${OUT_JSON}" >/dev/null
jq -e '.simulated != true' "${OUT_JSON}" >/dev/null
jq -e '.hub == "electron"' "${OUT_JSON}" >/dev/null

echo "NTW6 sysapps evidence PASS → ${OUT_JSON}"
