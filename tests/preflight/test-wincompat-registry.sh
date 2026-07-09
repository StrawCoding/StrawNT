#!/usr/bin/env bash
# W4-W1: strawwu-launcher ↔ strawwu-app-registry integration.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

COMPONENTS="${REPO_ROOT}/components"
LAUNCHER_DIR="${COMPONENTS}/strawwu-launcher"
REGISTRY_DIR="${COMPONENTS}/strawwu-app-registry"
SCHEMA="${REPO_ROOT}/docs/plans/schemas/app-registry.schema.json"
BASELINE="${BASELINES_DIR}/wincompat-registry-baseline.json"
STRAWWU_BIN="${COMPONENTS}/target/debug/strawwu"
BASELINE_YAML="${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml"

echo "=== W4-W1 wincompat-registry preflight ==="

require_plan "strawwu-windows-compat-integration-plan.md"
require_plan "strawwu-app-registry-plan.md"

require_file "${LAUNCHER_DIR}/src/registry.rs" "launcher registry.rs"
require_file "${REGISTRY_DIR}/src/registry.rs" "app-registry registry.rs"
require_file "${SCHEMA}" "app-registry.schema.json"
require_file "${BASELINE_YAML}" "wincompat baseline.yaml"

if grep -q 'upsert_from_launch' "${REGISTRY_DIR}/src/registry.rs"; then
    pass "RegistryStore upsert_from_launch"
else
    fail "RegistryStore missing upsert_from_launch"
fi

if grep -q 'register_launch' "${LAUNCHER_DIR}/src/registry.rs"; then
    pass "launcher register_launch bridge"
else
    fail "launcher missing register_launch"
fi

if grep -q 'strawwu-app-registry' "${LAUNCHER_DIR}/Cargo.toml"; then
    pass "launcher depends on strawwu-app-registry"
else
    fail "launcher missing app-registry dependency"
fi

if grep -q 'registry_path' "${BASELINE_YAML}"; then
    pass "baseline.yaml documents registry_path"
else
    fail "baseline.yaml missing registry_path"
fi

if grep -q 'run_registers' "${BASELINE_YAML}"; then
    pass "baseline.yaml documents run_registers"
else
    fail "baseline.yaml missing registry integration"
fi

if grep -q 'test-wincompat-registry:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-wincompat-registry"
else
    fail "Makefile missing test-wincompat-registry"
fi

if grep -q 'test-wincompat-registry.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes wincompat-registry"
else
    fail "preflight missing wincompat-registry gate"
fi

if (cd "${COMPONENTS}" && cargo build --package strawwu-launcher -q); then
    pass "cargo build strawwu-launcher"
else
    fail "cargo build strawwu-launcher"
fi

if (cd "${COMPONENTS}" && cargo test --package strawwu-launcher -q); then
    pass "cargo test strawwu-launcher"
else
    fail "cargo test strawwu-launcher"
fi

if (cd "${COMPONENTS}" && cargo test --package strawwu-app-registry -q); then
    pass "cargo test strawwu-app-registry"
else
    fail "cargo test strawwu-app-registry"
fi

require_file "${STRAWWU_BIN}" "strawwu binary"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
# Wiring smoke test: no real Windows binaries — opt into stub PE synthesis.
export STRAWWU_SMOKE=1
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
demo_exe="${tmp_dir}/games/demo-app.exe"
mkdir -p "$(dirname "${demo_exe}")"

if "${STRAWWU_BIN}" run "${demo_exe}" | grep -q 'app_id=demo-app'; then
    pass "strawwu run registers app_id"
else
    fail "strawwu run missing app_id in output"
fi

if [[ -f "${STRAWWU_APP_REGISTRY}" ]]; then
    pass "registry JSON written after run"
    validate_json_file "${STRAWWU_APP_REGISTRY}"
else
    fail "registry JSON not written"
fi

if python3 - <<PY "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
apps = data.get("apps", [])
app = next((a for a in apps if a.get("id") == "demo-app"), None)
assert app is not None, "demo-app missing"
assert app.get("kind") == "win32"
assert app.get("source") == "launcher"
assert app.get("install_state") == "installed"
assert app.get("execution_backend") == "native"
print("registry entry OK")
PY
then
    pass "registry entry shape after run"
else
    fail "registry entry shape invalid"
fi

if "${STRAWWU_BIN}" apps list | grep -q $'demo-app\tdemo-app\twin32'; then
    pass "strawwu apps list shows registered app"
else
    fail "strawwu apps list missing demo-app"
fi

if "${STRAWWU_BIN}" run "${demo_exe}" --backend container | grep -q 'backend=container'; then
    pass "strawwu run with backend override"
else
    fail "strawwu run backend override failed"
fi

if python3 - <<PY "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
app = next(a for a in data["apps"] if a["id"] == "demo-app")
assert app.get("execution_backend") == "container"
print("upsert backend OK")
PY
then
    pass "registry upsert updates backend"
else
    fail "registry upsert backend not updated"
fi

setup_exe="${tmp_dir}/setup.exe"
if "${STRAWWU_BIN}" install "${setup_exe}" | grep -q 'app_id=setup'; then
    pass "strawwu install registers pending app"
else
    fail "strawwu install registration failed"
fi

if python3 - <<PY "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
app = next(a for a in data["apps"] if a["id"] == "setup")
assert app.get("source") == "installer"
assert app.get("install_state") == "pending"
print("install pending OK")
PY
then
    pass "install pending registry entry"
else
    fail "install pending registry entry invalid"
fi

if "${STRAWWU_BIN}" status | grep -q '2 app(s) registered'; then
    pass "strawwu status reports registry count"
else
    fail "strawwu status registry count unexpected"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-wincompat-registry-baseline/v1",
    "wave": "W4-W1",
    "version": version,
    "launcher_crate": "strawwu-launcher",
    "registry_crate": "strawwu-app-registry",
    "registry_path": "/var/lib/strawwu/app-registry.json",
    "registry_env": "STRAWWU_APP_REGISTRY",
    "integration": {
        "run": {"registers": True, "source": "launcher", "upsert": True},
        "install": {"registers": True, "source": "installer", "state": "pending"},
        "apps_list": {"reads": "app-registry"},
        "status": {"reads": "app-registry"},
    },
    "dod": "strawwu run registers AppRecord in user app registry",
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "W4-W1 wincompat-registry"
