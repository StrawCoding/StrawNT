#!/usr/bin/env bash
# W6-W6: Windows compat E2E — install → desktop icon → launch → deep remove.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

COMPONENTS="${REPO_ROOT}/components"
LAUNCHER_DIR="${COMPONENTS}/strawwu-launcher"
REGISTRY_DIR="${COMPONENTS}/strawwu-app-registry"
DESKTOP_ACTIONS="${REPO_ROOT}/os-image/debs/strawwu-desktop-actions"
BASELINE="${BASELINES_DIR}/wincompat-e2e-baseline.json"
BASELINE_YAML="${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml"
E2E_SMOKE="${REPO_ROOT}/tests/e2e/wincompat-smoke.sh"
STRAWWU_BIN="${COMPONENTS}/target/debug/strawwu"
REGISTRY_BIN="${COMPONENTS}/target/debug/strawwu-app-registry"

echo "=== W6-W6 wincompat-e2e preflight ==="

require_plan "strawwu-windows-compat-integration-plan.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${LAUNCHER_DIR}/src/desktop.rs" "launcher desktop.rs"
require_file "${REGISTRY_DIR}/src/deep_remove.rs" "registry deep_remove.rs"
require_file "${DESKTOP_ACTIONS}/usr/lib/strawwu-desktop-actions/core.py" "desktop-actions core.py"
require_file "${BASELINE_YAML}" "wincompat baseline.yaml"

if grep -q 'e2e_flow:' "${BASELINE_YAML}"; then
    pass "baseline.yaml documents e2e_flow"
else
    fail "baseline.yaml missing e2e_flow"
fi

if grep -q 'test-wincompat-e2e:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-wincompat-e2e"
else
    fail "Makefile missing test-wincompat-e2e"
fi

if grep -q 'test-wincompat-e2e.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes wincompat-e2e gate"
else
    fail "preflight missing wincompat-e2e"
fi

require_file "${E2E_SMOKE}" "tests/e2e/wincompat-smoke.sh"

if (cd "${COMPONENTS}" && cargo build --package strawwu-launcher -q \
    && cargo build --package strawwu-app-registry -q); then
    pass "cargo build strawwu-launcher + app-registry"
else
    fail "cargo build wincompat E2E binaries"
fi

require_file "${STRAWWU_BIN}" "strawwu binary"
require_file "${REGISTRY_BIN}" "strawwu-app-registry binary"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
export STRAWWU_DESKTOP_DIR="${tmp_dir}/applications"
export STRAWWU_WINCOMPAT_LOG="${tmp_dir}/wincompat.log"
export STRAWWU_DEEP_REMOVE_ALLOW_PREFIXES="${tmp_dir}"
export STRAWWU_SKIP_FLATPAK_UNINSTALL=1
export HOME="${tmp_dir}/home"
export PATH="${COMPONENTS}/target/debug:${PATH}"
mkdir -p "${STRAWWU_DESKTOP_DIR}" "${HOME}"

app_prefix="${tmp_dir}/apps/notepad"
mkdir -p "${app_prefix}"
installer="${app_prefix}/setup.exe"
notepad_exe="${app_prefix}/notepad.exe"
touch "${installer}" "${notepad_exe}"

# --- Step 1: install (installer registration) ---
if "${STRAWWU_BIN}" install "${installer}" | grep -q 'app_id=setup'; then
    pass "E2E step install: strawwu install registers pending app"
else
    fail "E2E step install: install output missing app_id=setup"
fi

if python3 - <<PY "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
app = next((a for a in data.get("apps", []) if a.get("id") == "setup"), None)
assert app is not None, "setup missing"
assert app.get("source") == "installer"
assert app.get("install_state") == "pending"
print("install pending OK")
PY
then
    pass "E2E step install: registry pending entry"
else
    fail "E2E step install: registry pending entry invalid"
fi

# --- Step 2: run → desktop icon ---
if "${STRAWWU_BIN}" run "${notepad_exe}" | grep -q 'gui-smoke=PASS'; then
    pass "E2E step icon: strawwu run creates GUI smoke"
else
    fail "E2E step icon: run missing gui-smoke=PASS"
fi

desktop_file="${STRAWWU_DESKTOP_DIR}/notepad.desktop"
if [[ -f "${desktop_file}" ]]; then
    pass "E2E step icon: notepad.desktop created"
else
    fail "E2E step icon: desktop entry missing"
fi

if grep -q 'X-StrawWU-App-Id=notepad' "${desktop_file}" \
    && grep -q 'strawwu run' "${desktop_file}"; then
    pass "E2E step icon: desktop entry metadata + Exec"
else
    fail "E2E step icon: desktop entry incomplete"
fi

if python3 - <<PY "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
app = next((a for a in data.get("apps", []) if a.get("id") == "notepad"), None)
assert app is not None
assert app.get("install_state") == "installed"
assert app.get("desktop_entry")
assert "notepad.desktop" in app["desktop_entry"]
print("installed registry OK")
PY
then
    pass "E2E step icon: registry installed + desktop_entry"
else
    fail "E2E step icon: registry after run invalid"
fi

# --- Step 3: launch from desktop icon (parse Exec) ---
exec_line="$(grep -E '^Exec=' "${desktop_file}" | head -1 | cut -d= -f2-)"
if [[ -z "${exec_line}" ]]; then
    fail "E2E step launch: desktop Exec missing"
elif eval "${exec_line}" | grep -q 'app_id=notepad'; then
    pass "E2E step launch: desktop Exec relaunches app"
else
    fail "E2E step launch: desktop Exec launch failed"
fi

if [[ -f "${STRAWWU_WINCOMPAT_LOG}" ]] && grep -q 'gui_smoke' "${STRAWWU_WINCOMPAT_LOG}"; then
    pass "E2E step launch: wincompat.log records gui_smoke"
else
    fail "E2E step launch: wincompat.log missing gui_smoke"
fi

# --- Step 4: remove (remove-by-desktop --deep) ---
if "${REGISTRY_BIN}" remove-by-desktop "${desktop_file}" --deep --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
preview = d.get("preview", d)
assert d.get("registry_removed") is True or preview.get("id") == "notepad"
assert preview.get("id") == "notepad"
paths = d.get("paths_deleted", [])
assert any("notepad" in p for p in paths)
'; then
    pass "E2E step remove: remove-by-desktop --deep committed"
else
    fail "E2E step remove: remove-by-desktop --deep failed"
fi

if [[ ! -f "${desktop_file}" ]]; then
    pass "E2E step remove: desktop entry deleted"
else
    fail "E2E step remove: desktop entry still present"
fi

if ! "${REGISTRY_BIN}" list | grep -q $'notepad\t'; then
    pass "E2E step remove: notepad absent from registry list"
else
    fail "E2E step remove: notepad still listed"
fi

# desktop-actions orchestration (same path as context menu)
export STRAWWU_APP_REGISTRY_CLI="${REGISTRY_BIN}"
export STRAWWU_SKIP_FAVORITES_SYNC=1

demo_desktop="${tmp_dir}/demo2.desktop"
cat > "${demo_desktop}" <<EOF
[Desktop Entry]
Type=Application
Name=Demo Two
Exec=${STRAWWU_BIN} run ${notepad_exe}
X-StrawWU-App-Id=demo-two
EOF

"${REGISTRY_BIN}" register --id demo-two --name "Demo Two" --kind win32 --source manual \
    --install-path "${app_prefix}" --desktop-entry "${demo_desktop}" >/dev/null

if PYTHONPATH="${DESKTOP_ACTIONS}/usr/lib/strawwu-desktop-actions" \
    python3 - <<PY
import os
from pathlib import Path
from core import remove_desktop
p = Path("${demo_desktop}")
result = remove_desktop(p, dry_run=False, sync_favorites=False)
assert result["preview"]["id"] == "demo-two"
assert not p.exists()
print("desktop-actions remove OK")
PY
then
    pass "E2E remove via desktop-actions core.py"
else
    fail "E2E remove via desktop-actions core.py"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-wincompat-e2e-baseline/v1",
    "wave": "W6-W6",
    "version": version,
    "flow": ["install", "icon", "launch", "remove"],
    "smoke_script": "tests/e2e/wincompat-smoke.sh",
    "preflight": "tests/preflight/test-wincompat-e2e.sh",
    "cli": {
        "install": "strawwu install <installer.exe>",
        "icon": "strawwu run <app.exe> → ~/.local/share/applications/<id>.desktop",
        "launch": "desktop Exec → strawwu run",
        "remove": "strawwu-app-registry remove-by-desktop --deep",
    },
    "dod": "install→icon→launch→remove CLI E2E with registry + desktop-actions",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W6-W6 wincompat-e2e"
