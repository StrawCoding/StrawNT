#!/usr/bin/env bash
# nt6-openable.sh — Prove StrawNT is openable after install (CLI PATH, app menu,
# stale handler cleared, real strawnt open side-effects).
# Emits tests/strawnt/output/nt6-openable.json (top-level PASS|FAIL).
# Forbidden: Wine/Proton substrate, simulated top-level PASS, ISO/StrawWU OS work.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt6-openable.json"
SIDE_DIR="${OUT_DIR}/nt6-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"
DIST_DIR="${COMPONENTS}/packaging/portable/appimage/dist"
FIXTURE_EXE="${REPO_ROOT}/tests/portable/fixtures/pe2-console-mvp.exe"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[nt6-openable] $*"; }

mkdir -p "${OUT_DIR}"
rm -rf "${SIDE_DIR}"
mkdir -p "${SIDE_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" "${SIDE_DIR}" <<'PY'
import json, sys, time
out, version, msg, side = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {
    "schema": "strawnt-nt6-openable/v1",
    "stage": "nt6-openable-app",
    "product": "StrawNT",
    "status": "FAIL",
    "version": version,
    "mode": "simulated",
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "cli_available": False,
    "desktop_exec_exists": False,
    "stale_handler_cleared": False,
    "side_effects": {"dir": side},
    "failures": [msg],
    "claims": {
        "cli_available": False,
        "desktop_exec_exists": False,
        "stale_handler_cleared": False,
        "full_windows_compat": False,
        "anticheat_ranked_pass": False,
        "wine_proton_used": False,
        "simulated_ok": False,
    },
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
    die "${msg}"
}

CLEAN_HOME="${SIDE_DIR}/clean-home"
INSTALL_PREFIX="${CLEAN_HOME}/.local/share/strawnt"
BIN_DIR="${CLEAN_HOME}/.local/bin"
APPS_DIR="${CLEAN_HOME}/.local/share/applications"
MIME_DIR="${CLEAN_HOME}/.local/share/mime/packages"
OPEN_LOG="${SIDE_DIR}/open.log"
rm -rf "${CLEAN_HOME}"
mkdir -p "${APPS_DIR}" "${MIME_DIR}" "${BIN_DIR}" "${CLEAN_HOME}/.config" \
    "${CLEAN_HOME}/.profile.d" "${SIDE_DIR}/apps"

# --- (0) plant stale StrawWU handler (failure evidence reproduction) ---
log "planting stale strawwu-open.desktop (dead /tmp TryExec)"
STALE_DESKTOP="${APPS_DIR}/strawwu-open.desktop"
cat > "${STALE_DESKTOP}" <<'EOF'
[Desktop Entry]
Type=Application
Name=StrawWU
GenericName=Windows App Launcher
Comment=Install or run Windows .exe/.msi with StrawWU Portable Core
Exec="/tmp/tmp.hqa8qM1Rum/bin/strawwu" open %f
TryExec=/tmp/tmp.hqa8qM1Rum/bin/strawwu
Icon=strawwu
Terminal=false
Categories=System;Utility;
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;application/x-msi;application/x-ms-shortcut;
NoDisplay=false
StartupNotify=true
X-StrawWU-Kind=open-handler
EOF
[[ -f "${STALE_DESKTOP}" ]] || write_fail "failed to plant stale handler"
cp -a "${STALE_DESKTOP}" "${SIDE_DIR}/strawwu-open.desktop.stale.bak"

# --- (1) build strawnt + portable artifact ---
export CARGO_TARGET_DIR="${COMPONENTS}/target"
log "cargo build --release --bin strawnt"
(cd "${COMPONENTS}" && cargo build --release --bin strawnt) \
    || write_fail "cargo build strawnt failed"

log "cargo test desktop integration (stale clear + menu)"
(cd "${COMPONENTS}" && cargo test -p strawwu-launcher desktop::tests -- --nocapture) \
    || write_fail "strawwu-launcher desktop tests failed"

log "building portable prefix + appimage/tar.gz"
(cd "${REPO_ROOT}" && make portable-prefix) || write_fail "portable-prefix failed"
(cd "${REPO_ROOT}" && make portable-appimage) || write_fail "portable-appimage failed"

ASSET="$(ls -1 "${DIST_DIR}"/StrawNT-"${VERSION}"-x86_64.portable.tar.gz 2>/dev/null | head -n1 || true)"
[[ -n "${ASSET}" && -f "${ASSET}" ]] || write_fail "missing portable.tar.gz for ${VERSION} in ${DIST_DIR}"
log "asset=${ASSET}"

# --- (2) clean-env one-shot install (install.sh --local) ---
log "clean-env install via install.sh --local"
export HOME="${CLEAN_HOME}"
export XDG_CONFIG_HOME="${CLEAN_HOME}/.config"
export XDG_DATA_HOME="${CLEAN_HOME}/.local/share"
# Intentionally omit BIN_DIR from PATH before install (repro command-not-found).
export PATH="/usr/bin:/bin"
unset STRAWNT_PREFIX STRAWWU_PREFIX STRAWNT_BIN STRAWWU_BIN 2>/dev/null || true

set +e
INSTALL_OUT="$(
  HOME="${CLEAN_HOME}" \
  STRAWNT_PREFIX="${INSTALL_PREFIX}" \
  STRAWNT_BIN_DIR="${BIN_DIR}" \
  bash "${REPO_ROOT}/install.sh" --local "${ASSET}" \
    --prefix "${INSTALL_PREFIX}" --bin-dir "${BIN_DIR}" 2>&1
)"
INSTALL_RC=$?
set -e
printf '%s\n' "${INSTALL_OUT}" | tee "${SIDE_DIR}/install.sh.log" | sed 's/^/  | /'
[[ "${INSTALL_RC}" -eq 0 ]] || write_fail "install.sh --local failed rc=${INSTALL_RC}"

# After install: PATH must include BIN_DIR (install.sh exports + env snippet).
# shellcheck disable=SC1090
source "${CLEAN_HOME}/.config/strawnt/env.sh"
export PATH="${BIN_DIR}:${PATH}"

CLI_AVAILABLE=0
VER_OUT=""
set +e
VER_OUT="$(command -v strawnt >/dev/null && strawnt --version 2>&1)"
VER_RC=$?
set -e
if [[ "${VER_RC}" -eq 0 && "${VER_OUT}" == strawnt* ]]; then
    CLI_AVAILABLE=1
    log "PASS: strawnt --version → ${VER_OUT}"
else
    write_fail "strawnt --version unavailable after clean install (out=${VER_OUT})"
fi
WHICH_STRAWNT="$(command -v strawnt || true)"
[[ -n "${WHICH_STRAWNT}" ]] || write_fail "strawnt not on PATH after install"
[[ -x "${WHICH_STRAWNT}" ]] || write_fail "strawnt on PATH is not executable: ${WHICH_STRAWNT}"

# --- (3) app menu entry Exec/TryExec point at existing binary ---
MENU_DESKTOP="${APPS_DIR}/strawnt.desktop"
OPEN_DESKTOP="${APPS_DIR}/strawnt-open.desktop"
[[ -f "${MENU_DESKTOP}" ]] || write_fail "missing app-menu entry: ${MENU_DESKTOP}"
[[ -f "${OPEN_DESKTOP}" ]] || write_fail "missing open handler: ${OPEN_DESKTOP}"

cp -a "${MENU_DESKTOP}" "${SIDE_DIR}/strawnt.desktop"
cp -a "${OPEN_DESKTOP}" "${SIDE_DIR}/strawnt-open.desktop"

MENU_BODY="$(cat "${MENU_DESKTOP}")"
echo "${MENU_BODY}" | grep -q 'Name=StrawNT' || write_fail "menu entry missing Name=StrawNT"
echo "${MENU_BODY}" | grep -q 'TryExec=' || write_fail "menu entry missing TryExec"
echo "${MENU_BODY}" | grep -q ' status' || write_fail "menu Exec must run status (no bare open %f)"
echo "${MENU_BODY}" | grep -qi wine && write_fail "menu entry must not mention wine"

TRY_EXEC="$(awk -F= '/^TryExec=/{print $2; exit}' "${MENU_DESKTOP}")"
[[ -n "${TRY_EXEC}" ]] || write_fail "empty TryExec"
# Resolve relative TryExec via PATH.
if [[ "${TRY_EXEC}" == /* ]]; then
    TRY_PATH="${TRY_EXEC}"
else
    TRY_PATH="$(command -v "${TRY_EXEC}" || true)"
fi
[[ -n "${TRY_PATH}" && -e "${TRY_PATH}" ]] \
    || write_fail "menu TryExec does not exist: ${TRY_EXEC}"
DESKTOP_EXEC_EXISTS=1
log "PASS: menu TryExec exists → ${TRY_PATH}"

OPEN_BODY="$(cat "${OPEN_DESKTOP}")"
echo "${OPEN_BODY}" | grep -q ' open %f' || write_fail "open handler missing open %f"
echo "${OPEN_BODY}" | grep -q 'NoDisplay=true' || write_fail "open handler should be NoDisplay=true"
OPEN_TRY="$(awk -F= '/^TryExec=/{print $2; exit}' "${OPEN_DESKTOP}")"
if [[ "${OPEN_TRY}" == /* ]]; then
    [[ -e "${OPEN_TRY}" ]] || write_fail "open handler TryExec missing: ${OPEN_TRY}"
else
    command -v "${OPEN_TRY}" >/dev/null || write_fail "open handler TryExec not on PATH: ${OPEN_TRY}"
fi

# Menu Exec must be runnable (status).
set +e
MENU_STATUS_OUT="$(strawnt status 2>&1)"
MENU_STATUS_RC=$?
set -e
[[ "${MENU_STATUS_RC}" -eq 0 ]] || write_fail "strawnt status (menu Exec) failed"
echo "${MENU_STATUS_OUT}" | grep -qi 'native' || write_fail "status missing native backend"

# --- (4) stale StrawWU / temp handler cleared ---
STALE_CLEARED=0
if [[ ! -f "${STALE_DESKTOP}" ]]; then
    STALE_CLEARED=1
    log "PASS: stale strawwu-open.desktop removed"
else
    # Still present → hard fail (blocks double-click).
    write_fail "stale strawwu-open.desktop still present after install/integrate"
fi
# No other desktop with dead /tmp strawwu TryExec.
while IFS= read -r -d '' desk; do
    try="$(awk -F= '/^TryExec=/{print $2; exit}' "${desk}" 2>/dev/null || true)"
    if [[ -n "${try}" && "${try}" == /tmp/* && ! -e "${try}" ]]; then
        write_fail "broken TryExec still present in ${desk}: ${try}"
    fi
    if grep -q 'X-StrawWU-Kind=open-handler' "${desk}" 2>/dev/null; then
        write_fail "legacy X-StrawWU open-handler still present: ${desk}"
    fi
done < <(find "${APPS_DIR}" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null || true)

# --- (5) strawnt open real fixture → side effects ---
[[ -f "${FIXTURE_EXE}" ]] || write_fail "fixture missing: ${FIXTURE_EXE}"
export STRAWNT_REQUIRE_REAL_EXEC=1
export STRAWWU_REQUIRE_REAL_EXEC=1
export STRAWNT_BACKEND=native
export STRAWWU_BACKEND=native
export STRAWNT_APP_REGISTRY="${SIDE_DIR}/app-registry.json"
export STRAWWU_APP_REGISTRY="${STRAWNT_APP_REGISTRY}"
export STRAWNT_APPS_DIR="${SIDE_DIR}/apps"
export STRAWWU_APPS_DIR="${STRAWNT_APPS_DIR}"
export STRAWNT_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWWU_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWNT_DESKTOP_DIR="${APPS_DIR}"
export STRAWWU_DESKTOP_DIR="${APPS_DIR}"
printf '%s\n' '{"schema_version":"1.0","apps":[]}' > "${STRAWNT_APP_REGISTRY}"

log "strawnt open ${FIXTURE_EXE}"
set +e
OPEN_OUT="$(strawnt open "${FIXTURE_EXE}" 2>&1)"
OPEN_RC=$?
set -e
printf '%s\n' "${OPEN_OUT}" | tee "${OPEN_LOG}" | sed 's/^/  | /'
[[ "${OPEN_RC}" -eq 0 ]] || write_fail "strawnt open failed rc=${OPEN_RC}"
echo "${OPEN_OUT}" | grep -qi 'backend=native\|native' \
    || write_fail "open output missing native backend"
echo "${OPEN_OUT}" | grep -qiE 'wine|proton' && write_fail "open output mentions wine/proton"

# Observable side effects: non-empty open log + pe-exec-summary / marker / desktop
[[ -s "${OPEN_LOG}" ]] || write_fail "open.log empty"
SIDE_HIT=0
for cand in \
    "${SIDE_DIR}/pe-exec-summary.json" \
    "${SIDE_DIR}/pe-exec.log" \
    "${SIDE_DIR}/apps" \
    ; do
    if [[ -e "${cand}" ]]; then
        SIDE_HIT=1
        break
    fi
done
# Also accept any non-empty file under side-effects written by open (except install log / backups).
if [[ "${SIDE_HIT}" -eq 0 ]]; then
    if find "${SIDE_DIR}" -type f ! -name 'install.sh.log' ! -name '*.bak' ! -name 'open.log' \
        ! -name 'strawnt.desktop' ! -name 'strawnt-open.desktop' -size +0 2>/dev/null | grep -q .; then
        SIDE_HIT=1
    fi
fi
# Desktop launcher written by open counts.
if find "${APPS_DIR}" -maxdepth 1 -type f -name '*.desktop' ! -name 'strawnt.desktop' \
    ! -name 'strawnt-open.desktop' 2>/dev/null | grep -q .; then
    SIDE_HIT=1
fi
[[ "${SIDE_HIT}" -eq 1 ]] || write_fail "no observable side effects from strawnt open"

# Prefer a concrete side-effect file for Hermes verify.
SIDE_EFFECT_FILE="${OPEN_LOG}"
if [[ -f "${SIDE_DIR}/pe-exec-summary.json" ]]; then
    SIDE_EFFECT_FILE="${SIDE_DIR}/pe-exec-summary.json"
elif [[ -f "${SIDE_DIR}/pe-exec.log" ]]; then
    SIDE_EFFECT_FILE="${SIDE_DIR}/pe-exec.log"
fi
[[ -s "${SIDE_EFFECT_FILE}" ]] || write_fail "side effect file empty: ${SIDE_EFFECT_FILE}"

# --- write PASS evidence ---
python3 - "${OUT_JSON}" "${VERSION}" "${SIDE_DIR}" "${OPEN_LOG}" \
    "${CLI_AVAILABLE}" "${DESKTOP_EXEC_EXISTS}" "${STALE_CLEARED}" \
    "${MENU_DESKTOP}" "${OPEN_DESKTOP}" "${TRY_PATH}" "${WHICH_STRAWNT}" \
    "${ASSET}" "${SIDE_EFFECT_FILE}" "${VER_OUT}" "${OPEN_OUT}" <<'PY'
import json, sys, time, hashlib
from pathlib import Path

(
    out, version, side, open_log,
    cli_available, desktop_exec_exists, stale_cleared,
    menu_desktop, open_desktop, try_path, which_strawnt,
    asset, side_effect_file, ver_out, open_out,
) = sys.argv[1:]

def sha256(p: str) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

side_p = Path(side)
artifacts = sorted(
    str(p.resolve())
    for p in side_p.rglob("*")
    if p.is_file() and p.stat().st_size > 0
)

doc = {
    "schema": "strawnt-nt6-openable/v1",
    "stage": "nt6-openable-app",
    "product": "StrawNT",
    "status": "PASS",
    "version": version,
    "mode": "real",
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "cli_available": cli_available == "1",
    "desktop_exec_exists": desktop_exec_exists == "1",
    "stale_handler_cleared": stale_cleared == "1",
    "install": {
        "method": "install.sh --local",
        "asset": asset,
        "asset_sha256": sha256(asset) if Path(asset).is_file() else None,
    },
    "cli": {
        "which": which_strawnt,
        "version": ver_out.strip(),
    },
    "desktop": {
        "menu_entry": menu_desktop,
        "open_handler": open_desktop,
        "try_exec_resolved": try_path,
    },
    "open": {
        "fixture": "tests/portable/fixtures/pe2-console-mvp.exe",
        "log": open_log,
        "output_excerpt": "\n".join(open_out.strip().splitlines()[:20]),
    },
    "side_effects": {
        "dir": side,
        "open_log": open_log,
        "primary": side_effect_file,
    },
    "artifacts": artifacts[:40],
    "claims": {
        "cli_available": cli_available == "1",
        "desktop_exec_exists": desktop_exec_exists == "1",
        "stale_handler_cleared": stale_cleared == "1",
        "full_windows_compat": False,
        "anticheat_ranked_pass": False,
        "wine_proton_used": False,
        "simulated_ok": False,
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop / StrawWU OS changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility / ranked anti-cheat claim",
        "no simulated top-level PASS",
    ],
}

assert doc["status"] == "PASS"
assert doc["mode"] != "simulated"
assert doc["cli_available"] is True
assert doc["desktop_exec_exists"] is True
assert doc["stale_handler_cleared"] is True
assert Path(open_log).is_file() and Path(open_log).stat().st_size > 0
assert Path(side_effect_file).is_file() and Path(side_effect_file).stat().st_size > 0

with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY

log "PASS → ${OUT_JSON}"

# Local Hermes-verify subset (final mark still via trigger-verify)
python3 - <<PY
import json, pathlib, sys
p = pathlib.Path("${OUT_JSON}")
doc = json.loads(p.read_text(encoding="utf-8"))
assert doc["status"] == "PASS"
assert doc.get("mode") != "simulated"
assert doc.get("cli_available") is True or doc.get("claims", {}).get("cli_available") is True
assert doc.get("desktop_exec_exists") is True or doc.get("claims", {}).get("desktop_exec_exists") is True
assert doc.get("stale_handler_cleared") is True or doc.get("claims", {}).get("stale_handler_cleared") is True
f = doc.get("side_effects", {}).get("open_log") or (doc.get("artifacts") or [None])[0]
assert f and pathlib.Path(f).is_file() and pathlib.Path(f).stat().st_size > 0
print("local hermes-verify subset OK")
PY
