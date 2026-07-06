#!/usr/bin/env bash
# W6-R5: registry deep remove — allowlisted path deletion + scan uninstall sync.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

CRATE_DIR="${REPO_ROOT}/components/strawwu-app-registry"
COMPONENTS="${REPO_ROOT}/components"
DESKTOP_ACTIONS="${REPO_ROOT}/os-image/debs/strawwu-desktop-actions"
MANIFEST="${DESKTOP_ACTIONS}/usr/share/strawwu/app-registry/deep-uninstall-manifest.yaml"
BASELINE="${BASELINES_DIR}/deep-uninstall-baseline.json"
SECURITY="${PLANS_DIR}/strawwu-security-trust-model.md"
REGISTRY_BIN="${COMPONENTS}/target/debug/strawwu-app-registry"

echo "=== W6-R5 deep-uninstall preflight ==="

require_plan "strawwu-app-registry-plan.md"
require_file "${SECURITY}" "security trust model"
require_file "${CRATE_DIR}/src/deep_remove.rs" "deep_remove.rs module"
require_file "${MANIFEST}" "deep-uninstall-manifest.yaml"
require_file "${BASELINE}" "deep-uninstall-baseline.json"

if grep -q 'deep_remove' "${CRATE_DIR}/src/lib.rs" \
    && grep -q 'deep_remove' "${CRATE_DIR}/src/registry.rs"; then
    pass "deep_remove wired into registry crate"
else
    fail "deep_remove not exported from registry crate"
fi

if grep -q 'deep-remove' "${CRATE_DIR}/src/cli.rs" \
    && grep -q 'DeepRemove' "${CRATE_DIR}/src/cli.rs"; then
    pass "CLI deep-remove command"
else
    fail "CLI missing deep-remove"
fi

if grep -q 'sync_removed_from_scan' "${CRATE_DIR}/src/registry.rs"; then
    pass "scan uninstall sync API"
else
    fail "sync_removed_from_scan missing"
fi

if grep -q 'forbidden_prefixes' "${MANIFEST}" \
    && grep -q '/usr' "${MANIFEST}" \
    && grep -q 'allow_prefixes' "${MANIFEST}"; then
    pass "manifest documents allow/forbidden prefixes"
else
    fail "deep-uninstall manifest incomplete"
fi

if grep -qi 'deep uninstall' "${SECURITY}" && grep -q 'allowlist' "${SECURITY}"; then
    pass "security model documents deep uninstall allowlist"
else
    fail "security trust model missing deep uninstall policy"
fi

if grep -q 'remove-by-desktop.*--deep' "${DESKTOP_ACTIONS}/usr/lib/strawwu-desktop-actions/core.py"; then
    pass "desktop remove uses deep-remove-by-desktop"
else
    fail "desktop-actions core.py missing --deep remove"
fi

if grep -q "deep-remove" "${COMPONENTS}/strawwu-hub/src/main/app-registry-service.js"; then
    pass "Hub remove defaults to deep-remove"
else
    fail "Hub app-registry-service missing deep-remove"
fi

if grep -q 'test-deep-uninstall:' "${REPO_ROOT}/Makefile"; then
    pass "Makefile defines test-deep-uninstall"
else
    fail "Makefile missing test-deep-uninstall"
fi

if grep -q 'test-deep-uninstall.sh' "${REPO_ROOT}/Makefile"; then
    pass "preflight includes deep-uninstall gate"
else
    fail "preflight missing deep-uninstall"
fi

if (cd "${COMPONENTS}" && cargo build --package strawwu-app-registry -q); then
    pass "cargo build strawwu-app-registry"
else
    fail "cargo build strawwu-app-registry"
fi

if (cd "${COMPONENTS}" && cargo test --package strawwu-app-registry -q); then
    pass "cargo test strawwu-app-registry (deep_remove + registry)"
else
    fail "cargo test strawwu-app-registry"
fi

require_file "${REGISTRY_BIN}" "strawwu-app-registry binary"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
export STRAWWU_APP_REGISTRY="${tmp_dir}/app-registry.json"
export STRAWWU_APP_REGISTRY_LOG="${tmp_dir}/app-registry.log"
export STRAWWU_DEEP_REMOVE_ALLOW_PREFIXES="${tmp_dir}"
export STRAWWU_SKIP_FLATPAK_UNINSTALL=1

app_tree="${tmp_dir}/demo-app"
mkdir -p "${app_tree}/data"
echo "payload" > "${app_tree}/data/file.txt"

if "${REGISTRY_BIN}" register --id demo-app --name "Demo App" --kind win32 --source installer \
    --install-path "${app_tree}"; then
    pass "CLI register demo app for deep-remove"
else
    fail "CLI register demo app"
fi

if "${REGISTRY_BIN}" deep-remove demo-app --dry-run --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["dry_run"] is True
assert d["registry_removed"] is False
assert d["preview"]["id"] == "demo-app"
assert any("demo-app" in p for p in d["paths_deleted"])
'; then
    pass "CLI deep-remove dry-run JSON"
else
    fail "CLI deep-remove dry-run JSON"
fi

if [[ -d "${app_tree}" ]]; then
    pass "dry-run preserved install tree"
else
    fail "dry-run deleted install tree"
fi

if "${REGISTRY_BIN}" list | grep -q 'demo-app'; then
    pass "dry-run left registry entry active"
else
    fail "dry-run unexpectedly removed registry entry"
fi

if "${REGISTRY_BIN}" deep-remove demo-app --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["registry_removed"] is True
assert d["preview"]["id"] == "demo-app"
'; then
    pass "CLI deep-remove committed"
else
    fail "CLI deep-remove committed"
fi

if [[ ! -d "${app_tree}" ]]; then
    pass "deep-remove deleted allowlisted install tree"
else
    fail "deep-remove did not delete install tree"
fi

if ! "${REGISTRY_BIN}" list | grep -q 'demo-app'; then
    pass "deep-remove removed registry listing"
else
    fail "deep-remove left app in list"
fi

if "${REGISTRY_BIN}" register --id blocked-linux --name Blocked --kind linux --source manual \
    --install-path /usr/bin/blocked --desktop-entry /usr/share/applications/blocked.desktop \
    && "${REGISTRY_BIN}" deep-remove blocked-linux --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert len(d["paths_skipped"]) >= 1
assert len(d["paths_deleted"]) == 0
'; then
    pass "system paths skipped during deep-remove"
else
    fail "system path guard failed"
fi

# scan-remove sync: flatpak entry absent from fixture list
export STRAWWU_FLATPAK_LIST_FILE="${tmp_dir}/flatpak.list"
echo "com.spotify.client	Spotify" > "${STRAWWU_FLATPAK_LIST_FILE}"
"${REGISTRY_BIN}" register --id org.gnome.calculator --name Calculator --kind flatpak \
    --source flatpak --install-path org.gnome.Calculator >/dev/null

if "${REGISTRY_BIN}" scan --flatpak --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
removed = d.get("removed", [])
assert any(r.get("id") == "org.gnome.calculator" for r in removed), removed
'; then
    pass "scan sync marks missing flatpak removed"
else
    fail "scan sync missing flatpak remove"
fi

if ! "${REGISTRY_BIN}" list | grep -q 'org.gnome.calculator'; then
    pass "scan-synced flatpak absent from list"
else
    fail "scan-synced flatpak still listed"
fi

validate_json_file "${BASELINE}"

preflight_exit "W6-R5 deep-uninstall"
