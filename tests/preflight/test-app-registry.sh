#!/usr/bin/env bash
# W2-R1: strawwu-app-registry — crate, CLI, JSON schema.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CRATE_DIR="${REPO_ROOT}/components/strawwu-app-registry"
SCHEMA="${REPO_ROOT}/docs/plans/schemas/app-registry.schema.json"
FIXTURE="${CRATE_DIR}/tests/fixtures/sample-registry.json"
COMPONENTS="${REPO_ROOT}/components"

echo "=== W2-R1 app-registry preflight ==="

require_plan "strawwu-app-registry-plan.md"
require_plan "strawwu-security-trust-model.md"

if [[ -f "${REPO_ROOT}/components/strawwu-nt/src/installer.rs" ]]; then
    if grep -q 'struct AppDatabase' "${REPO_ROOT}/components/strawwu-nt/src/installer.rs"; then
        pass "AppDatabase stub in strawwu-nt (separate from user registry)"
    else
        fail "AppDatabase stub missing in strawwu-nt"
    fi
else
    fail "components/strawwu-nt/src/installer.rs missing"
fi

require_file "${CRATE_DIR}/Cargo.toml" "strawwu-app-registry Cargo.toml"
require_file "${CRATE_DIR}/src/lib.rs" "strawwu-app-registry lib.rs"
require_file "${CRATE_DIR}/src/main.rs" "strawwu-app-registry main.rs"
require_file "${CRATE_DIR}/src/cli.rs" "strawwu-app-registry cli.rs"
require_file "${CRATE_DIR}/src/registry.rs" "strawwu-app-registry registry.rs"
require_file "${CRATE_DIR}/src/validate.rs" "strawwu-app-registry validate.rs"
require_file "${SCHEMA}" "app-registry.schema.json"
require_file "${FIXTURE}" "sample-registry fixture"

if grep -q 'strawwu-app-registry' "${COMPONENTS}/Cargo.toml"; then
    pass "workspace member strawwu-app-registry"
else
    fail "strawwu-app-registry missing from components/Cargo.toml workspace"
fi

validate_json_file "${SCHEMA}"
validate_json_file "${FIXTURE}"

if grep -q '"const": "1.0"' "${SCHEMA}"; then
    pass "schema_version 1.0 frozen"
else
    fail "schema missing schema_version 1.0 const"
fi

if grep -q 'protected' "${SCHEMA}" && grep -q 'protected app' "${PLANS_DIR}/strawwu-security-trust-model.md"; then
    pass "protected flag aligned with security trust model"
else
    fail "protected flag not documented in schema or trust model"
fi

# Cargo build + unit tests
if (cd "${COMPONENTS}" && cargo build --package strawwu-app-registry -q); then
    pass "cargo build strawwu-app-registry"
else
    fail "cargo build strawwu-app-registry"
fi

if (cd "${COMPONENTS}" && cargo test --package strawwu-app-registry -q); then
    pass "cargo test strawwu-app-registry"
else
    fail "cargo test strawwu-app-registry"
fi

BIN="${COMPONENTS}/target/debug/strawwu-app-registry"
require_file "${BIN}" "strawwu-app-registry binary"

# CLI integration in temp dir
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"

if "${BIN}" version | grep -q 'strawwu-app-registry'; then
    pass "CLI version"
else
    fail "CLI version"
fi

if "${BIN}" validate "${FIXTURE}"; then
    pass "CLI validate fixture"
else
    fail "CLI validate fixture"
fi

if "${BIN}" register --id demo-app --name "Demo App" --kind win32 --source installer \
    --install-path /opt/strawwu/apps/demo; then
    pass "CLI register"
else
    fail "CLI register"
fi

if "${BIN}" list | grep -q 'demo-app'; then
    pass "CLI list"
else
    fail "CLI list"
fi

if "${BIN}" show demo-app --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["id"]=="demo-app"'; then
    pass "CLI show --json"
else
    fail "CLI show --json"
fi

if "${BIN}" remove demo-app --dry-run | grep -q 'dry-run'; then
    pass "CLI remove --dry-run"
else
    fail "CLI remove --dry-run"
fi

if "${BIN}" list | grep -q 'demo-app'; then
    pass "dry-run did not remove app"
else
    fail "dry-run unexpectedly removed app"
fi

if "${BIN}" remove demo-app; then
    pass "CLI remove"
else
    fail "CLI remove"
fi

if ! "${BIN}" list | grep -q 'demo-app'; then
    pass "removed app absent from list"
else
    fail "removed app still listed"
fi

if "${BIN}" validate; then
    pass "CLI validate default path"
else
    fail "CLI validate default path"
fi

if [[ -f "${STRAWWU_APP_REGISTRY}" ]]; then
    pass "registry JSON written"
    validate_json_file "${STRAWWU_APP_REGISTRY}"
else
    fail "registry JSON not written"
fi

if "${BIN}" register --id protected-app --name Protected --kind native --source seed --protected \
    && ! "${BIN}" remove protected-app 2>/dev/null; then
    pass "protected app remove rejected"
else
    fail "protected app remove should fail"
fi

# Bug-reporter bundle.py expects apps[] with id/name/protected
if python3 - <<'PY' "${STRAWWU_APP_REGISTRY}"
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
apps = data.get("apps", [])
assert isinstance(apps, list)
assert any(a.get("id") == "protected-app" and a.get("protected") is True for a in apps)
print("bug-reporter summary shape OK")
PY
then
    pass "bug-reporter registry summary shape"
else
    fail "bug-reporter registry summary shape"
fi

preflight_exit "W2-R1 app-registry"
