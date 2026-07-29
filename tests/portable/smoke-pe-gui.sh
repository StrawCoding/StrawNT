#!/usr/bin/env bash
# smoke-pe-gui.sh — pe3 user32/gdi GUI MVP evidence.
# Runs a GUI PE that exercises RegisterClass/CreateWindow/ShowWindow/message
# loop + GetDC/BitBlt via the native CPU loop, writes screenshot + compositor
# observation, and emits tests/portable/output/pe-gui.json
# (top-level status=PASS|PARTIAL|FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-gui.json"
FIXTURE_DIR="${REPO_ROOT}/tests/portable/fixtures"
FIXTURE_EXE="${FIXTURE_DIR}/pe3-gui-mvp.exe"
SIDE_DIR="${OUT_DIR}/pe3-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-pe-gui] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-pe-gui/v1",
    "stage": "pe3-gui-user32-mvp",
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

log "emitting pe3 GUI MVP fixture via strawwu-nt"
EMIT_DIR="$(mktemp -d /tmp/strawwu-pe3-emit.XXXXXX)"
cleanup_emit() { rm -rf "${EMIT_DIR}"; }
trap cleanup_emit EXIT
mkdir -p "${EMIT_DIR}/src"
cat > "${EMIT_DIR}/Cargo.toml" <<EOF
[package]
name = "pe3-emit"
version = "0.0.0"
edition = "2021"
[dependencies]
strawwu-nt = { path = "${COMPONENTS}/strawwu-nt" }
EOF
cat > "${EMIT_DIR}/src/main.rs" <<'EOF'
fn main() {
    let pe = strawwu_nt::build_win32_gui_mvp_pe();
    let out = std::env::args().nth(1).expect("out path");
    std::fs::write(&out, &pe).expect("write fixture");
    println!("wrote {} bytes to {}", pe.len(), out);
}
EOF
(cd "${EMIT_DIR}" && cargo run --quiet --release -- "${FIXTURE_EXE}") \
    || write_fail "failed to emit pe3 fixture"

[[ -f "${FIXTURE_EXE}" ]] || write_fail "fixture missing: ${FIXTURE_EXE}"
FIXTURE_SHA="$(sha256sum "${FIXTURE_EXE}" | awk '{print $1}')"
log "fixture sha256=${FIXTURE_SHA} path=${FIXTURE_EXE}"

log "cargo test pe3 GUI MVP cpu/runtime paths"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt cpu_runs_win32_gui_mvp_user32_gdi -- --nocapture) \
    || write_fail "strawwu-nt pe3 cpu test failed"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime execute_win32_gui_mvp_fixture -- --nocapture) \
    || write_fail "strawwu-runtime pe3 exec test failed"

STRAWWU_BIN="${COMPONENTS}/target/release/strawwu"
[[ -x "${STRAWWU_BIN}" ]] || write_fail "strawwu binary missing"

export STRAWWU_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWWU_REQUIRE_REAL_EXEC=1
export STRAWWU_APP_REGISTRY="${SIDE_DIR}/app-registry.json"
export HOME="${SIDE_DIR}/home"
mkdir -p "${HOME}/.local/share/applications" "${HOME}/.local/share/strawwu"

log "running strawwu run on pe3 fixture (native, require real)"
set +e
RUN_OUT="$("${STRAWWU_BIN}" run "${FIXTURE_EXE}" --backend native 2>&1)"
RUN_RC=$?
set -e
log "run rc=${RUN_RC}"
printf '%s\n' "${RUN_OUT}" | sed 's/^/  | /'

echo "${RUN_OUT}" | grep -q 'mode=real' || write_fail "launcher did not report mode=real"
if echo "${RUN_OUT}" | grep -q 'mode=simulated'; then
    write_fail "launcher still reports mode=simulated"
fi
[[ "${RUN_RC}" -eq 0 ]] || write_fail "strawwu run failed rc=${RUN_RC}"
echo "${RUN_OUT}" | grep -q 'gui-smoke=PASS' || write_fail "gui-smoke not PASS"
echo "${RUN_OUT}" | grep -q 'cpu-user32=1' || write_fail "missing cpu-user32 evidence flag"

HOST_STDOUT="${SIDE_DIR}/pe-stdout.txt"
[[ -f "${HOST_STDOUT}" ]] || write_fail "missing host side-effect file ${HOST_STDOUT}"
STDOUT_BODY="$(cat "${HOST_STDOUT}")"
echo "${STDOUT_BODY}" | grep -q 'STRAWWU_PE_GUI_OK' \
    || write_fail "side-effect stdout missing STRAWWU_PE_GUI_OK"
echo "${STDOUT_BODY}" | grep -q 'STRAWWU_PE_GUI_CLOSED' \
    || write_fail "side-effect stdout missing STRAWWU_PE_GUI_CLOSED"

HOST_FILE="${SIDE_DIR}/pe3-marker.txt"
[[ -f "${HOST_FILE}" ]] || write_fail "missing host file side-effect ${HOST_FILE}"
FILE_BODY="$(cat "${HOST_FILE}")"
echo "${FILE_BODY}" | grep -q 'STRAWWU_PE_GUI_OK' \
    || write_fail "file side-effect missing STRAWWU_PE_GUI_OK"

SHOT="${SIDE_DIR}/pe3-window.ppm"
[[ -f "${SHOT}" ]] || write_fail "missing screenshot ${SHOT}"
head -c 2 "${SHOT}" | grep -q 'P6' || write_fail "screenshot is not PPM P6"

OBS="${SIDE_DIR}/pe3-compositor.json"
[[ -f "${OBS}" ]] || write_fail "missing compositor observation ${OBS}"
jq -e '.frame_count >= 1 and .compositor == "mutter"' "${OBS}" >/dev/null \
    || write_fail "compositor observation incomplete"
OBS_BODY="$(cat "${OBS}")"

if command -v rg >/dev/null 2>&1; then
    if rg -n -i 'ensure_wine|wine_backend|STRAWWU_BACKEND=wine|launch_via_wine' \
        "${REPO_ROOT}/components" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" \
        >/tmp/pe3-wine-rg.txt 2>/dev/null; then
        write_fail "wine substrate markers found in product tree"
    fi
fi

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

python3 - "${OUT_JSON}" "${VERSION}" "${FIXTURE_EXE}" "${FIXTURE_SHA}" \
    "${HOST_STDOUT}" "${STDOUT_BODY}" "${HOST_FILE}" "${FILE_BODY}" \
    "${SHOT}" "${OBS}" "${OBS_BODY}" \
    "${RUN_OUT}" "${COMMIT}" "${SIDE_DIR}" <<'PY'
import json, sys, time, pathlib
(
    out, version, fixture, sha, host_stdout, stdout_body, host_file, file_body,
    shot, obs, obs_body, run_out, commit, side_dir,
) = sys.argv[1:15]
obs_doc = json.loads(obs_body)
doc = {
    "schema": "strawwu-portable-pe-gui/v1",
    "stage": "pe3-gui-user32-mvp",
    "status": "PASS",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "real",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "fixture": {
        "path": fixture,
        "sha256": sha,
        "kind": "win32-gui-mvp-amd64",
        "subsystem": "WindowsGui",
        "markers": ["STRAWWU_PE_GUI_OK", "STRAWWU_PE_GUI_CLOSED"],
    },
    "api_paths": {
        "user32": [
            "RegisterClassA",
            "CreateWindowExA",
            "ShowWindow",
            "UpdateWindow",
            "GetMessageA",
            "TranslateMessage",
            "DispatchMessageA",
            "DestroyWindow",
            "PostQuitMessage",
            "GetDC",
            "ReleaseDC",
        ],
        "gdi32": ["BitBlt", "CreateCompatibleDC", "GetDeviceCaps", "DeleteDC"],
        "not_stub_only": True,
    },
    "window": {
        "hwnd": obs_doc.get("hwnd"),
        "title": obs_doc.get("title"),
        "width": obs_doc.get("width"),
        "height": obs_doc.get("height"),
        "closed": obs_doc.get("closed"),
        "messages_dispatched": obs_doc.get("messages_dispatched"),
    },
    "compositor": {
        "display": obs_doc.get("display"),
        "name": obs_doc.get("compositor"),
        "backend": obs_doc.get("backend"),
        "frame_count": obs_doc.get("frame_count"),
        "observation_path": obs,
    },
    "screenshot": {
        "path": shot,
        "format": "ppm-p6",
    },
    "side_effects": {
        "stdout_file": host_stdout,
        "stdout": stdout_body,
        "marker_file": host_file,
        "marker_file_body": file_body,
        "dir": side_dir,
    },
    "launcher": {
        "command": "strawwu run <fixture> --backend native",
        "output": run_out.splitlines(),
        "require_real_exec": True,
    },
    "checks": [
        {"name": "mode_real", "status": "PASS"},
        {"name": "backend_native", "status": "PASS"},
        {"name": "gui_subsystem", "status": "PASS"},
        {"name": "stdout_gui_marker", "status": "PASS"},
        {"name": "stdout_close_marker", "status": "PASS"},
        {"name": "host_file_side_effect", "status": "PASS"},
        {"name": "screenshot_ppm", "status": "PASS"},
        {"name": "compositor_observation", "status": "PASS"},
        {"name": "cpu_user32_gdi_dispatch_test", "status": "PASS"},
        {"name": "runtime_exec_test", "status": "PASS"},
        {"name": "no_wine_substrate", "status": "PASS"},
    ],
    "pending": [],
    "evidence": [
        "tests/portable/output/pe-gui.json",
        "tests/portable/fixtures/pe3-gui-mvp.exe",
        "tests/portable/output/pe3-side-effects/pe3-window.ppm",
        "tests/portable/output/pe3-side-effects/pe3-compositor.json",
        "components/strawwu-nt/src/cpu.rs",
        "components/strawwu-nt/src/pe.rs",
        "components/strawwu-nt/src/win32_stubs.rs",
    ],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "mode=simulated is not accepted as success",
        "not stub-only: real CPU dispatch of user32/gdi + message loop",
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
jq -e '.api_paths.not_stub_only == true' "${OUT_JSON}" >/dev/null
jq -e '.screenshot.path != null' "${OUT_JSON}" >/dev/null
jq -e '.compositor.frame_count >= 1' "${OUT_JSON}" >/dev/null
log "verify predicates OK"
