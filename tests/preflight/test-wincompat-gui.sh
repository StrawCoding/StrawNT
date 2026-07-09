#!/usr/bin/env bash
# W5-W4: Windows GUI app launch smoke — Win32 HWND + Wayland present bridge + desktop entry.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

COMPONENTS="${REPO_ROOT}/components"
LAUNCHER_DIR="${COMPONENTS}/strawwu-launcher"
RUNTIME_DIR="${COMPONENTS}/strawwu-runtime"
BASELINE="${BASELINES_DIR}/wincompat-gui-baseline.json"
BASELINE_YAML="${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml"
STRAWWU_BIN="${COMPONENTS}/target/debug/strawwu"

echo "=== W5-W4 wincompat-gui preflight ==="

require_plan "strawwu-windows-compat-integration-plan.md"
require_plan "strawwu-prd-v0.5.md"

require_file "${RUNTIME_DIR}/src/gui_smoke.rs" "runtime gui_smoke.rs"
require_file "${LAUNCHER_DIR}/src/desktop.rs" "launcher desktop.rs"
require_file "${LAUNCHER_DIR}/src/log.rs" "launcher wincompat log"
require_file "${LAUNCHER_DIR}/src/pe_loader.rs" "launcher pe_loader.rs"
require_file "${BASELINE_YAML}" "wincompat baseline.yaml"

if grep -q 'gui_smoke:' "${BASELINE_YAML}"; then
    pass "baseline.yaml documents gui_smoke"
else
    fail "baseline.yaml missing gui_smoke"
fi

if grep -q 'test-wincompat-gui:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-wincompat-gui"
else
    fail "Makefile missing test-wincompat-gui"
fi

if grep -q 'test-wincompat-gui.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes wincompat-gui"
else
    fail "preflight missing wincompat-gui gate"
fi

if (cd "${COMPONENTS}" && cargo build --package strawwu-launcher -q); then
    pass "cargo build strawwu-launcher"
else
    fail "cargo build strawwu-launcher"
fi

if (cd "${COMPONENTS}" && cargo test --package strawwu-runtime gui_smoke -q); then
    pass "cargo test gui_smoke"
else
    fail "cargo test gui_smoke"
fi

if (cd "${COMPONENTS}" && cargo test --package strawwu-launcher desktop -q); then
    pass "cargo test launcher desktop"
else
    fail "cargo test launcher desktop"
fi

require_file "${STRAWWU_BIN}" "strawwu binary"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
export STRAWWU_DESKTOP_DIR="${tmp_dir}/applications"
# Wiring smoke test: no real Windows binary — opt into stub PE synthesis.
export STRAWWU_SMOKE=1
export STRAWWU_WINCOMPAT_LOG="${tmp_dir}/wincompat.log"
notepad_exe="${tmp_dir}/notepad.exe"

if "${STRAWWU_BIN}" run "${notepad_exe}" | grep -q 'gui-smoke=PASS'; then
    pass "strawwu run notepad gui-smoke PASS"
else
    fail "strawwu run notepad gui-smoke output missing"
fi

if "${STRAWWU_BIN}" run "${notepad_exe}" | grep -q 'compositor=mutter'; then
    pass "strawwu run reports mutter compositor"
else
    fail "strawwu run missing compositor=mutter"
fi

desktop_file="${STRAWWU_DESKTOP_DIR}/notepad.desktop"
if [[ -f "${desktop_file}" ]]; then
    pass "desktop entry notepad.desktop created"
else
    fail "desktop entry missing"
fi

if grep -q 'X-StrawWU-App-Id=notepad' "${desktop_file}"; then
    pass "desktop entry X-StrawWU-App-Id"
else
    fail "desktop entry missing X-StrawWU-App-Id"
fi

if [[ -f "${STRAWWU_WINCOMPAT_LOG}" ]] && grep -q 'gui_smoke' "${STRAWWU_WINCOMPAT_LOG}"; then
    pass "wincompat.log gui_smoke event"
else
    fail "wincompat.log missing gui_smoke"
fi

if python3 - <<PY "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
app = next((a for a in data.get("apps", []) if a.get("id") == "notepad"), None)
assert app is not None, "notepad missing"
assert app.get("kind") == "win32"
assert app.get("desktop_entry"), "desktop_entry missing"
assert "notepad.desktop" in app["desktop_entry"]
print("registry desktop_entry OK")
PY
then
    pass "registry desktop_entry after gui run"
else
    fail "registry desktop_entry invalid"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-wincompat-gui-baseline/v1",
    "wave": "W5-W4",
    "version": version,
    "runtime_module": "strawwu-runtime/gui_smoke.rs",
    "launcher_modules": ["desktop.rs", "log.rs", "pe_loader.rs"],
    "smoke_app": "notepad.exe",
    "compositor": "mutter",
    "display_backend_default": "wayland",
    "log_path": "/var/log/strawwu/wincompat.log",
    "desktop_dir_default": "~/.local/share/applications",
    "dod": "GUI PE app smoke: Win32 window + present bridge + desktop entry",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W5-W4 wincompat-gui"
