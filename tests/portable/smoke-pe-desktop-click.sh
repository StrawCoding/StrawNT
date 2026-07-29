#!/usr/bin/env bash
# smoke-pe-desktop-click.sh — pe5 MIME/integrate + menu re-launch evidence.
# Proves: integrate writes native-only MIME handler; double-click open
# (strawwu open) installs/launches; app-menu .desktop re-launches via
# --backend native; install.sh has no Wine. Emits pe-desktop-click.json.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-desktop-click.json"
FIXTURE_DIR="${REPO_ROOT}/tests/portable/fixtures"
FIXTURE_EXE="${FIXTURE_DIR}/pe4-setup.exe"
SIDE_DIR="${OUT_DIR}/pe5-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-pe-desktop-click] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-pe-desktop-click/v1",
    "stage": "pe5-desktop-click",
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

STRAWWU_BIN="${COMPONENTS}/target/release/strawwu"
[[ -x "${STRAWWU_BIN}" ]] || write_fail "strawwu binary missing"
export STRAWWU_BIN

# Ensure pe4 native installer fixture exists (reuse emitter if needed).
if [[ ! -f "${FIXTURE_EXE}" ]]; then
    log "emitting pe4 installer fixture for pe5 click path"
    EMIT_DIR="$(mktemp -d /tmp/strawwu-pe5-emit.XXXXXX)"
    cleanup_emit() { rm -rf "${EMIT_DIR}"; }
    trap cleanup_emit EXIT
    mkdir -p "${EMIT_DIR}/src"
    cat > "${EMIT_DIR}/Cargo.toml" <<EOF
[package]
name = "pe5-emit"
version = "0.0.0"
edition = "2021"
[dependencies]
strawwu-nt = { path = "${COMPONENTS}/strawwu-nt" }
EOF
    cat > "${EMIT_DIR}/src/main.rs" <<'EOF'
fn main() {
    let (sfx, _msi) = strawwu_nt::build_pe4_installer_fixtures().expect("fixtures");
    let out = std::env::args().nth(1).expect("exe out");
    std::fs::write(&out, &sfx).expect("write exe");
}
EOF
    (cd "${EMIT_DIR}" && cargo run --quiet --release -- "${FIXTURE_EXE}") \
        || write_fail "failed to emit pe5 fixture"
    trap - EXIT
    cleanup_emit
fi
[[ -f "${FIXTURE_EXE}" ]] || write_fail "fixture missing: ${FIXTURE_EXE}"
EXE_SHA="$(sha256sum "${FIXTURE_EXE}" | awk '{print $1}')"

log "cargo test desktop integration"
(cd "${COMPONENTS}" && cargo test -p strawwu-launcher desktop::tests -- --nocapture) \
    || write_fail "strawwu-launcher desktop tests failed"

# Isolated desktop/MIME dirs (simulates post-install integrate).
# Must set HOME *after* cargo test so rustup still finds its toolchain.
export HOME="${SIDE_DIR}/home"
export STRAWWU_DESKTOP_DIR="${HOME}/.local/share/applications"
export STRAWWU_MIME_DIR="${HOME}/.local/share/mime/packages"
export STRAWWU_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWWU_REQUIRE_REAL_EXEC=1
export STRAWWU_APP_REGISTRY="${SIDE_DIR}/app-registry.json"
export STRAWWU_APPS_DIR="${SIDE_DIR}/apps"
export STRAWWU_BACKEND=native
mkdir -p "${STRAWWU_DESKTOP_DIR}" "${STRAWWU_MIME_DIR}" \
    "${HOME}/.local/share/strawwu" "${STRAWWU_APPS_DIR}"

# --- integrate (MIME + open handler) ---
log "strawwu integrate (native MIME handler)"
set +e
INTEGRATE_OUT="$("${STRAWWU_BIN}" integrate 2>&1)"
INTEGRATE_RC=$?
set -e
log "integrate rc=${INTEGRATE_RC}"
printf '%s\n' "${INTEGRATE_OUT}" | sed 's/^/  | /'
[[ "${INTEGRATE_RC}" -eq 0 ]] || write_fail "strawwu integrate failed rc=${INTEGRATE_RC}"
echo "${INTEGRATE_OUT}" | grep -qi 'backend: native' \
    || write_fail "integrate missing backend: native marker"

HANDLER="${STRAWWU_DESKTOP_DIR}/strawwu-open.desktop"
MIME_XML="${STRAWWU_MIME_DIR}/strawwu-win32.xml"
[[ -f "${HANDLER}" ]] || write_fail "open handler missing: ${HANDLER}"
[[ -f "${MIME_XML}" ]] || write_fail "MIME package missing: ${MIME_XML}"
HANDLER_BODY="$(cat "${HANDLER}")"
echo "${HANDLER_BODY}" | grep -q ' open %f' || write_fail "handler Exec missing open %f"
echo "${HANDLER_BODY}" | grep -q 'MimeType=' || write_fail "handler missing MimeType"
echo "${HANDLER_BODY}" | grep -q 'application/x-ms-dos-executable' \
    || write_fail "handler missing exe MIME"
echo "${HANDLER_BODY}" | grep -q 'application/x-msi' \
    || write_fail "handler missing msi MIME"
echo "${HANDLER_BODY}" | grep -q 'X-StrawWU-Backend=native' \
    || write_fail "handler missing X-StrawWU-Backend=native"
echo "${HANDLER_BODY}" | grep -qi wine && write_fail "handler must not mention wine"
grep -q '\.exe' "${MIME_XML}" || write_fail "MIME xml missing *.exe glob"
grep -q '\.msi' "${MIME_XML}" || write_fail "MIME xml missing *.msi glob"

# --- double-click open (same as MIME Exec: strawwu open %f) ---
log "strawwu open <setup.exe> (double-click install+launch)"
# Deliberately poison env: open path must still pin native.
export STRAWWU_BACKEND=container
set +e
OPEN_OUT="$("${STRAWWU_BIN}" open --install "${FIXTURE_EXE}" 2>&1)"
OPEN_RC=$?
set -e
# Keep STRAWWU_BACKEND=container — menu Exec must still pin --backend native.
log "open rc=${OPEN_RC}"
printf '%s\n' "${OPEN_OUT}" | sed 's/^/  | /'
[[ "${OPEN_RC}" -eq 0 ]] || write_fail "strawwu open failed rc=${OPEN_RC}"
echo "${OPEN_OUT}" | grep -q 'native unpack' || write_fail "open missing native unpack"
echo "${OPEN_OUT}" | grep -q 'backend=native' || write_fail "open missing backend=native"
echo "${OPEN_OUT}" | grep -q 'mode=real' || write_fail "open missing mode=real"
if echo "${OPEN_OUT}" | grep -q 'mode=simulated'; then
    write_fail "open still reports mode=simulated"
fi

APP_ID="pe4-setup"
INSTALL_ROOT="${STRAWWU_APPS_DIR}/${APP_ID}"
MAIN_EXE="${INSTALL_ROOT}/main.exe"
MENU_DESKTOP="${STRAWWU_DESKTOP_DIR}/${APP_ID}.desktop"
[[ -f "${MAIN_EXE}" ]] || write_fail "open did not unpack main.exe"
[[ -f "${MENU_DESKTOP}" ]] || write_fail "app-menu desktop missing after open"
MENU_BODY="$(cat "${MENU_DESKTOP}")"
echo "${MENU_BODY}" | grep -q 'run --backend native' \
    || write_fail "menu Exec must pin --backend native"
echo "${MENU_BODY}" | grep -q 'main.exe' || write_fail "menu Exec must point at main.exe"
echo "${MENU_BODY}" | grep -q 'X-StrawWU-Backend=native' \
    || write_fail "menu missing X-StrawWU-Backend=native"
echo "${MENU_BODY}" | grep -qi wine && write_fail "menu desktop must not mention wine"

HOST_STDOUT="${SIDE_DIR}/pe-stdout.txt"
[[ -f "${HOST_STDOUT}" ]] || write_fail "missing host side-effect from first open launch"
grep -q 'STRAWWU_PE_CONSOLE_OK' "${HOST_STDOUT}" \
    || write_fail "first launch missing STRAWWU_PE_CONSOLE_OK"
FIRST_STDOUT_SHA="$(sha256sum "${HOST_STDOUT}" | awk '{print $1}')"

# --- menu shortcut re-launch (選單捷徑可再開) ---
log "re-launch via app-menu desktop Exec (native)"
rm -f "${HOST_STDOUT}"
# Parse Exec= line and run it (simulates clicking the menu entry).
MENU_EXEC="$(python3 - "${MENU_DESKTOP}" <<'PY'
import sys
from pathlib import Path
body = Path(sys.argv[1]).read_text()
for line in body.splitlines():
    if line.startswith("Exec="):
        print(line[len("Exec="):])
        break
else:
    raise SystemExit("no Exec=")
PY
)"
[[ -n "${MENU_EXEC}" ]] || write_fail "failed to parse menu Exec"
# Desktop Entry quotes args; evaluate safely via bash -c with the Exec string.
set +e
# shellcheck disable=SC2086
RELAUNCH_OUT="$(bash -c "${MENU_EXEC}" 2>&1)"
RELAUNCH_RC=$?
set -e
log "menu re-launch rc=${RELAUNCH_RC}"
printf '%s\n' "${RELAUNCH_OUT}" | sed 's/^/  | /'
[[ "${RELAUNCH_RC}" -eq 0 ]] || write_fail "menu re-launch failed rc=${RELAUNCH_RC}"
echo "${RELAUNCH_OUT}" | grep -q 'backend=native' \
    || write_fail "menu re-launch missing backend=native"
echo "${RELAUNCH_OUT}" | grep -q 'mode=real' \
    || write_fail "menu re-launch missing mode=real"
[[ -f "${HOST_STDOUT}" ]] || write_fail "menu re-launch produced no side-effect stdout"
grep -q 'STRAWWU_PE_CONSOLE_OK' "${HOST_STDOUT}" \
    || write_fail "menu re-launch missing STRAWWU_PE_CONSOLE_OK"
SECOND_STDOUT_SHA="$(sha256sum "${HOST_STDOUT}" | awk '{print $1}')"

# --- install.sh / product tree: no Wine ---
log "scan install.sh README components for Wine substrate markers"
if command -v rg >/dev/null 2>&1; then
    if rg -n -i 'ensure_wine|wine_backend|STRAWWU_BACKEND=wine' \
        "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" "${REPO_ROOT}/components" \
        >/tmp/pe5-wine-rg.txt 2>/dev/null; then
        write_fail "wine substrate markers found (see /tmp/pe5-wine-rg.txt)"
    fi
else
    if grep -RniE 'ensure_wine|wine_backend|STRAWWU_BACKEND=wine' \
        "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" "${REPO_ROOT}/components" \
        >/tmp/pe5-wine-rg.txt 2>/dev/null; then
        write_fail "wine substrate markers found (see /tmp/pe5-wine-rg.txt)"
    fi
fi
# install.sh must default STRAWWU_BACKEND to native and call integrate.
grep -q 'STRAWWU_BACKEND=.*native' "${REPO_ROOT}/install.sh" \
    || write_fail "install.sh missing STRAWWU_BACKEND default native"
grep -q 'integrate' "${REPO_ROOT}/install.sh" \
    || write_fail "install.sh missing strawwu integrate for click-to-open"
! grep -qiE 'apt.*wine|ensure_wine|STRAWWU_BACKEND=wine' "${REPO_ROOT}/install.sh" \
    || write_fail "install.sh still provisions Wine"

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

python3 - "${OUT_JSON}" "${VERSION}" "${FIXTURE_EXE}" "${EXE_SHA}" \
    "${HANDLER}" "${HANDLER_BODY}" "${MIME_XML}" \
    "${MENU_DESKTOP}" "${MENU_BODY}" "${MAIN_EXE}" \
    "${INTEGRATE_OUT}" "${OPEN_OUT}" "${RELAUNCH_OUT}" \
    "${FIRST_STDOUT_SHA}" "${SECOND_STDOUT_SHA}" \
    "${COMMIT}" "${SIDE_DIR}" <<'PY'
import json, sys, time, pathlib
(
    out, version, exe_path, exe_sha, handler, handler_body, mime_xml,
    menu_desktop, menu_body, main_exe, integrate_out, open_out, relaunch_out,
    first_sha, second_sha, commit, side_dir,
) = sys.argv[1:18]
doc = {
    "schema": "strawwu-portable-pe-desktop-click/v1",
    "stage": "pe5-desktop-click",
    "status": "PASS",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "real",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "integrate": {
        "command": "strawwu integrate",
        "handler": handler,
        "mime_xml": mime_xml,
        "backend": "native",
        "output": integrate_out.splitlines(),
        "body_preview": handler_body.splitlines()[:16],
    },
    "double_click_open": {
        "command": "strawwu open --install <pe4-setup.exe>",
        "equiv_mime_exec": "strawwu open %f",
        "fixture": {"path": exe_path, "sha256": exe_sha},
        "main_exe": main_exe,
        "forced_env_STRAWWU_BACKEND": "container",
        "still_native": True,
        "output": open_out.splitlines(),
        "side_effect_stdout_sha256": first_sha,
    },
    "menu_relaunch": {
        "desktop": menu_desktop,
        "exec_pins_backend_native": "--backend native" in menu_body,
        "x_strawwu_backend": "native" in menu_body,
        "output": relaunch_out.splitlines(),
        "side_effect_stdout_sha256": second_sha,
    },
    "install_sh": {
        "path": "install.sh",
        "defaults_backend_native": True,
        "calls_integrate": True,
        "no_wine_provision": True,
    },
    "checks": [
        {"name": "integrate_mime_handler_native", "status": "PASS"},
        {"name": "mime_xml_exe_msi", "status": "PASS"},
        {"name": "double_click_open_install_launch", "status": "PASS"},
        {"name": "open_ignores_non_native_env", "status": "PASS"},
        {"name": "menu_shortcut_pins_native", "status": "PASS"},
        {"name": "menu_relaunch_mode_real", "status": "PASS"},
        {"name": "install_sh_no_wine", "status": "PASS"},
        {"name": "no_wine_substrate", "status": "PASS"},
    ],
    "pending": [],
    "evidence": [
        "tests/portable/output/pe-desktop-click.json",
        "install.sh",
        "components/strawwu-launcher/src/desktop.rs",
        "components/strawwu-launcher/src/main.rs",
        "tests/portable/smoke-pe-desktop-click.sh",
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
jq -e '.status == "PASS"' "${OUT_JSON}" >/dev/null
jq -e '.backend == "native" or .execution_backend == "native"' "${OUT_JSON}" >/dev/null
jq -e '.mode == "real"' "${OUT_JSON}" >/dev/null
jq -e '.menu_relaunch.exec_pins_backend_native == true' "${OUT_JSON}" >/dev/null
jq -e '.install_sh.no_wine_provision == true' "${OUT_JSON}" >/dev/null
log "verify predicates OK"
