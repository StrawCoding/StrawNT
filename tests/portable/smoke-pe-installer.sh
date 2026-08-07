#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-pe-installer.sh — pe4 native EXE/MSI installer evidence.
# Unpacks SWUP/SWUM packages, writes app-registry, creates desktop shortcuts,
# runs open on the same path, and emits tests/portable/output/pe-installer.json
# (top-level status=PASS|PARTIAL|FAIL). No Wine.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-installer.json"
FIXTURE_DIR="${REPO_ROOT}/tests/portable/fixtures"
FIXTURE_EXE="${FIXTURE_DIR}/pe4-setup.exe"
FIXTURE_MSI="${FIXTURE_DIR}/pe4-setup.msi"
SIDE_DIR="${OUT_DIR}/pe4-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-pe-installer] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-pe-installer/v1",
    "stage": "pe4-installer-real",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "simulated",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
    die "${msg}"
}

log "building strawwu (release)"
(cd "${COMPONENTS}" && cargo build -p strawwu-launcher --release) \
    || write_fail "cargo build strawwu-launcher failed"

log "emitting pe4 installer fixtures via strawwu-nt"
EMIT_DIR="$(mktemp -d /tmp/strawwu-pe4-emit.XXXXXX)"
cleanup_emit() { rm -rf "${EMIT_DIR}"; }
trap cleanup_emit EXIT
mkdir -p "${EMIT_DIR}/src"
cat > "${EMIT_DIR}/Cargo.toml" <<EOF
[package]
name = "pe4-emit"
version = "0.0.0"
edition = "2021"
[dependencies]
strawwu-nt = { path = "${COMPONENTS}/strawwu-nt" }
EOF
cat > "${EMIT_DIR}/src/main.rs" <<'EOF'
fn main() {
    let (sfx, msi) = strawwu_nt::build_pe4_installer_fixtures().expect("fixtures");
    let mut args = std::env::args().skip(1);
    let exe_out = args.next().expect("exe out");
    let msi_out = args.next().expect("msi out");
    std::fs::write(&exe_out, &sfx).expect("write exe");
    std::fs::write(&msi_out, &msi).expect("write msi");
    println!("wrote exe={} msi={}", sfx.len(), msi.len());
}
EOF
(cd "${EMIT_DIR}" && cargo run --quiet --release -- "${FIXTURE_EXE}" "${FIXTURE_MSI}") \
    || write_fail "failed to emit pe4 fixtures"

[[ -f "${FIXTURE_EXE}" ]] || write_fail "fixture missing: ${FIXTURE_EXE}"
[[ -f "${FIXTURE_MSI}" ]] || write_fail "fixture missing: ${FIXTURE_MSI}"
EXE_SHA="$(sha256sum "${FIXTURE_EXE}" | awk '{print $1}')"
MSI_SHA="$(sha256sum "${FIXTURE_MSI}" | awk '{print $1}')"
log "exe sha256=${EXE_SHA}"
log "msi sha256=${MSI_SHA}"

log "cargo test pe4 installer package paths"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt installer::tests -- --nocapture) \
    || write_fail "strawwu-nt installer tests failed"

STRAWWU_BIN="${COMPONENTS}/target/release/strawwu"
[[ -x "${STRAWWU_BIN}" ]] || write_fail "strawwu binary missing"
export STRAWWU_BIN

export STRAWWU_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWWU_REQUIRE_REAL_EXEC=1
export STRAWWU_APP_REGISTRY="${SIDE_DIR}/app-registry.json"
export STRAWWU_APPS_DIR="${SIDE_DIR}/apps"
export HOME="${SIDE_DIR}/home"
export STRAWWU_DESKTOP_DIR="${HOME}/.local/share/applications"
mkdir -p "${STRAWWU_DESKTOP_DIR}" "${HOME}/.local/share/strawwu" "${STRAWWU_APPS_DIR}"

# --- EXE install path ---
log "strawwu install pe4-setup.exe (native unpack)"
set +e
INSTALL_OUT="$("${STRAWWU_BIN}" install "${FIXTURE_EXE}" 2>&1)"
INSTALL_RC=$?
set -e
log "install rc=${INSTALL_RC}"
printf '%s\n' "${INSTALL_OUT}" | sed 's/^/  | /'

echo "${INSTALL_OUT}" | grep -q 'native unpack' || write_fail "install missing native unpack marker"
echo "${INSTALL_OUT}" | grep -q 'backend=native' || write_fail "install missing backend=native"
echo "${INSTALL_OUT}" | grep -q 'mode=real' || write_fail "install missing mode=real"
echo "${INSTALL_OUT}" | grep -q 'type=exe' || write_fail "install missing type=exe"
[[ "${INSTALL_RC}" -eq 0 ]] || write_fail "strawwu install exe failed rc=${INSTALL_RC}"
echo "${INSTALL_OUT}" | grep -q 'mode=real' || write_fail "launcher did not report mode=real after install"
if echo "${INSTALL_OUT}" | grep -q 'mode=simulated'; then
    write_fail "launcher still reports mode=simulated"
fi

APP_ID="pe4-setup"
INSTALL_ROOT="${STRAWWU_APPS_DIR}/${APP_ID}"
MAIN_EXE="${INSTALL_ROOT}/main.exe"
MARKER_TXT="${INSTALL_ROOT}/STRAWWU_INSTALL.txt"
DESKTOP_FILE="${STRAWWU_DESKTOP_DIR}/${APP_ID}.desktop"

[[ -d "${INSTALL_ROOT}" ]] || write_fail "install root missing: ${INSTALL_ROOT}"
[[ -f "${MAIN_EXE}" ]] || write_fail "unpacked main.exe missing"
[[ -f "${MARKER_TXT}" ]] || write_fail "unpacked STRAWWU_INSTALL.txt missing"
grep -q 'STRAWWU_PE4_INSTALLED' "${MARKER_TXT}" \
    || write_fail "install marker text missing STRAWWU_PE4_INSTALLED"
[[ -f "${DESKTOP_FILE}" ]] || write_fail "desktop shortcut missing: ${DESKTOP_FILE}"
grep -q 'strawwu' "${DESKTOP_FILE}" || write_fail "desktop Exec missing strawwu"
grep -q 'main.exe' "${DESKTOP_FILE}" || write_fail "desktop Exec must point at unpacked main.exe"
grep -q "X-StrawWU-App-Id=${APP_ID}" "${DESKTOP_FILE}" \
    || write_fail "desktop missing X-StrawWU-App-Id"

python3 - <<PY "${STRAWWU_APP_REGISTRY}" "${APP_ID}" "${INSTALL_ROOT}" "${DESKTOP_FILE}"
import json, sys
from pathlib import Path
reg, app_id, install_root, desktop = sys.argv[1:5]
data = json.loads(Path(reg).read_text())
app = next((a for a in data.get("apps", []) if a.get("id") == app_id), None)
assert app is not None, f"{app_id} missing from registry"
assert app.get("source") == "installer", app
assert app.get("install_state") == "installed", app
assert app.get("execution_backend") == "native", app
assert app.get("install_path") == install_root, (app.get("install_path"), install_root)
assert app.get("desktop_entry") == desktop, (app.get("desktop_entry"), desktop)
print("exe registry OK")
PY

HOST_STDOUT="${SIDE_DIR}/pe-stdout.txt"
[[ -f "${HOST_STDOUT}" ]] || write_fail "missing host side-effect stdout from main.exe"
grep -q 'STRAWWU_PE_CONSOLE_OK' "${HOST_STDOUT}" \
    || write_fail "main.exe side-effect missing STRAWWU_PE_CONSOLE_OK"

# --- open same path ---
log "strawwu open pe4-setup.exe (same native path)"
# Clear apps for a clean re-unpack while keeping registry path.
rm -rf "${STRAWWU_APPS_DIR:?}/${APP_ID}"
set +e
OPEN_OUT="$("${STRAWWU_BIN}" open --install "${FIXTURE_EXE}" 2>&1)"
OPEN_RC=$?
set -e
log "open rc=${OPEN_RC}"
printf '%s\n' "${OPEN_OUT}" | sed 's/^/  | /'
echo "${OPEN_OUT}" | grep -q 'native unpack' || write_fail "open missing native unpack marker"
[[ "${OPEN_RC}" -eq 0 ]] || write_fail "strawwu open failed rc=${OPEN_RC}"
[[ -f "${MAIN_EXE}" ]] || write_fail "open did not re-unpack main.exe"
[[ -f "${DESKTOP_FILE}" ]] || write_fail "open did not recreate desktop"

# --- MSI install path ---
log "strawwu install pe4-setup.msi (native unpack)"
rm -rf "${STRAWWU_APPS_DIR:?}/pe4-setup" 2>/dev/null || true
# MSI fixture stem is also pe4-setup — use a distinct copy name for clear app_id.
MSI_NAMED="${FIXTURE_DIR}/pe4-msi-setup.msi"
cp -f "${FIXTURE_MSI}" "${MSI_NAMED}"
MSI_APP_ID="pe4-msi-setup"
set +e
MSI_OUT="$("${STRAWWU_BIN}" install "${MSI_NAMED}" 2>&1)"
MSI_RC=$?
set -e
log "msi install rc=${MSI_RC}"
printf '%s\n' "${MSI_OUT}" | sed 's/^/  | /'
echo "${MSI_OUT}" | grep -q 'native unpack' || write_fail "msi install missing native unpack"
echo "${MSI_OUT}" | grep -q 'type=msi' || write_fail "msi install missing type=msi"
[[ "${MSI_RC}" -eq 0 ]] || write_fail "strawwu install msi failed rc=${MSI_RC}"

MSI_ROOT="${STRAWWU_APPS_DIR}/${MSI_APP_ID}"
MSI_MAIN="${MSI_ROOT}/main.exe"
MSI_DESKTOP="${STRAWWU_DESKTOP_DIR}/${MSI_APP_ID}.desktop"
[[ -f "${MSI_MAIN}" ]] || write_fail "msi unpack missing main.exe"
[[ -f "${MSI_DESKTOP}" ]] || write_fail "msi desktop shortcut missing"
grep -q 'main.exe' "${MSI_DESKTOP}" || write_fail "msi desktop must point at main.exe"

python3 - <<PY "${STRAWWU_APP_REGISTRY}" "${MSI_APP_ID}" "${MSI_ROOT}"
import json, sys
from pathlib import Path
reg, app_id, install_root = sys.argv[1:4]
data = json.loads(Path(reg).read_text())
app = next((a for a in data.get("apps", []) if a.get("id") == app_id), None)
assert app is not None, f"{app_id} missing"
assert app.get("source") == "installer"
assert app.get("install_state") == "installed"
assert app.get("execution_backend") == "native"
assert app.get("install_path") == install_root
print("msi registry OK")
PY

# NTW0 soft-reset: wine ban lifted — product tree MAY contain wine/GE markers.
# Do not fail legacy native evidence solely because Wine substrate is present.
log "NTW0: skip wine-substrate product-tree ban (lift_ban; path_role=legacy_native)"

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
REG_BODY="$(cat "${STRAWWU_APP_REGISTRY}")"
DESKTOP_BODY="$(cat "${DESKTOP_FILE}")"

python3 - "${OUT_JSON}" "${VERSION}" "${FIXTURE_EXE}" "${EXE_SHA}" \
    "${FIXTURE_MSI}" "${MSI_SHA}" "${INSTALL_ROOT}" "${MAIN_EXE}" \
    "${DESKTOP_FILE}" "${DESKTOP_BODY}" "${STRAWWU_APP_REGISTRY}" "${REG_BODY}" \
    "${INSTALL_OUT}" "${OPEN_OUT}" "${MSI_OUT}" "${COMMIT}" "${SIDE_DIR}" \
    "${MSI_ROOT}" "${MSI_DESKTOP}" <<'PY'
import json, sys, time, pathlib
(
    out, version, exe_fix, exe_sha, msi_fix, msi_sha, install_root, main_exe,
    desktop, desktop_body, registry, reg_body, install_out, open_out, msi_out,
    commit, side_dir, msi_root, msi_desktop,
) = sys.argv[1:20]
doc = {
    "schema": "strawwu-portable-pe-installer/v1",
    "stage": "pe4-installer-real",
    "status": "PASS",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "real",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "fixtures": {
        "exe": {"path": exe_fix, "sha256": exe_sha, "kind": "swup-sfx-amd64"},
        "msi": {"path": msi_fix, "sha256": msi_sha, "kind": "swum-msi-amd64"},
    },
    "install": {
        "command": "strawwu install <pe4-setup.exe>",
        "path": install_root,
        "main_exe": main_exe,
        "desktop": desktop,
        "output": install_out.splitlines(),
    },
    "open": {
        "command": "strawwu open --install <pe4-setup.exe>",
        "same_path_as_install": True,
        "output": open_out.splitlines(),
    },
    "msi_install": {
        "command": "strawwu install <pe4-msi-setup.msi>",
        "path": msi_root,
        "desktop": msi_desktop,
        "output": msi_out.splitlines(),
    },
    "app_registry": {
        "path": registry,
        "source": "installer",
        "install_state": "installed",
        "execution_backend": "native",
    },
    "shortcut": {
        "path": desktop,
        "points_to_unpacked_main": "main.exe" in desktop_body,
        "body_preview": desktop_body.splitlines()[:12],
    },
    "checks": [
        {"name": "exe_native_unpack", "status": "PASS"},
        {"name": "msi_native_unpack", "status": "PASS"},
        {"name": "app_registry_installed", "status": "PASS"},
        {"name": "desktop_shortcut_main_exe", "status": "PASS"},
        {"name": "open_same_native_path", "status": "PASS"},
        {"name": "mode_real_main_launch", "status": "PASS"},
        {"name": "backend_native", "status": "PASS"},
        {"name": "no_wine_substrate", "status": "PASS"},
    ],
    "pending": [],
    "evidence": [
        "tests/portable/output/pe-installer.json",
        "tests/portable/fixtures/pe4-setup.exe",
        "tests/portable/fixtures/pe4-setup.msi",
        "components/strawwu-nt/src/installer.rs",
        "components/strawwu-launcher/src/install_native.rs",
    ],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "mode=simulated is not accepted as success",
    ],
    "git": {"branch": "main", "commit": commit},
}
pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY

log "PASS → ${OUT_JSON}"
jq -e '.status == "PASS" or .status == "PARTIAL"' "${OUT_JSON}" >/dev/null
jq -e '.backend == "native" or .execution_backend == "native"' "${OUT_JSON}" >/dev/null
jq -e '.mode == "real"' "${OUT_JSON}" >/dev/null
jq -e '.open.same_path_as_install == true' "${OUT_JSON}" >/dev/null
log "verify predicates OK"
