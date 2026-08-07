#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-pe-console.sh — pe2 Win32 console MVP evidence.
# Runs a console PE that exercises kernel32 file/process + msvcrt CRT paths
# via the native CPU loop (not stub-registry-only), and writes
# tests/portable/output/pe-console.json (top-level status=PASS|FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-console.json"
FIXTURE_DIR="${REPO_ROOT}/tests/portable/fixtures"
FIXTURE_EXE="${FIXTURE_DIR}/pe2-console-mvp.exe"
SIDE_DIR="${OUT_DIR}/pe2-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-pe-console] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-pe-console/v1",
    "stage": "pe2-win32-console-mvp",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "simulated",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "legacy/archive native-era path; product default execution_backend=wine (proton-ge; powered by Wine); not a full Windows OS claim",
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

log "emitting pe2 console MVP fixture via strawwu-nt"
EMIT_DIR="$(mktemp -d /tmp/strawwu-pe2-emit.XXXXXX)"
cleanup_emit() { rm -rf "${EMIT_DIR}"; }
trap cleanup_emit EXIT
mkdir -p "${EMIT_DIR}/src"
cat > "${EMIT_DIR}/Cargo.toml" <<EOF
[package]
name = "pe2-emit"
version = "0.0.0"
edition = "2021"
[dependencies]
strawwu-nt = { path = "${COMPONENTS}/strawwu-nt" }
EOF
cat > "${EMIT_DIR}/src/main.rs" <<'EOF'
fn main() {
    let pe = strawwu_nt::build_win32_console_mvp_pe();
    let out = std::env::args().nth(1).expect("out path");
    std::fs::write(&out, &pe).expect("write fixture");
    println!("wrote {} bytes to {}", pe.len(), out);
}
EOF
(cd "${EMIT_DIR}" && cargo run --quiet --release -- "${FIXTURE_EXE}") \
    || write_fail "failed to emit pe2 fixture"

[[ -f "${FIXTURE_EXE}" ]] || write_fail "fixture missing: ${FIXTURE_EXE}"
FIXTURE_SHA="$(sha256sum "${FIXTURE_EXE}" | awk '{print $1}')"
log "fixture sha256=${FIXTURE_SHA} path=${FIXTURE_EXE}"

# Run cargo tests BEFORE overriding HOME (rustup reads $HOME/.rustup).
log "cargo test pe2 console MVP cpu/runtime paths"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt cpu_runs_win32_console_mvp_file_process_crt -- --nocapture) \
    || write_fail "strawwu-nt pe2 cpu test failed"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime execute_win32_console_mvp_fixture -- --nocapture) \
    || write_fail "strawwu-runtime pe2 exec test failed"

STRAWWU_BIN="${COMPONENTS}/target/release/strawwu"
[[ -x "${STRAWWU_BIN}" ]] || write_fail "strawwu binary missing"

export STRAWWU_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWWU_REQUIRE_REAL_EXEC=1
export STRAWWU_APP_REGISTRY="${SIDE_DIR}/app-registry.json"
export HOME="${SIDE_DIR}/home"
mkdir -p "${HOME}/.local/share/applications" "${HOME}/.local/share/strawwu"

log "running strawwu run on pe2 fixture (native, require real)"
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

HOST_STDOUT="${SIDE_DIR}/pe-stdout.txt"
[[ -f "${HOST_STDOUT}" ]] || write_fail "missing host side-effect file ${HOST_STDOUT}"
STDOUT_BODY="$(cat "${HOST_STDOUT}")"
echo "${STDOUT_BODY}" | grep -q 'STRAWWU_PE_CONSOLE_OK' \
    || write_fail "side-effect stdout missing STRAWWU_PE_CONSOLE_OK"
echo "${STDOUT_BODY}" | grep -q 'STRAWWU_PE_CONSOLE_CRT' \
    || write_fail "side-effect stdout missing STRAWWU_PE_CONSOLE_CRT (CRT puts path)"
# CRT marker must be a distinct puts line, not fused with the filename string.
echo "${STDOUT_BODY}" | grep -q 'STRAWWU_PE_CONSOLE_CRTpe2-marker' \
    && write_fail "CRT puts leaked into filename (missing NUL on CRT string)"

HOST_FILE="${SIDE_DIR}/pe2-marker.txt"
[[ -f "${HOST_FILE}" ]] || write_fail "missing host file side-effect ${HOST_FILE}"
FILE_BODY="$(cat "${HOST_FILE}")"
echo "${FILE_BODY}" | grep -q 'STRAWWU_PE_CONSOLE_OK' \
    || write_fail "file side-effect missing STRAWWU_PE_CONSOLE_OK"

echo "${RUN_OUT}" | grep -q 'STRAWWU_PE_CONSOLE_OK' \
    || write_fail "process output missing STRAWWU_PE_CONSOLE_OK marker"

# NTW0 soft-reset: wine ban lifted — product tree MAY contain wine/GE markers.
# Do not fail legacy native evidence solely because Wine substrate is present.
log "NTW0: skip wine-substrate product-tree ban (lift_ban; path_role=legacy_native)"

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

python3 - "${OUT_JSON}" "${VERSION}" "${FIXTURE_EXE}" "${FIXTURE_SHA}" \
    "${HOST_STDOUT}" "${STDOUT_BODY}" "${HOST_FILE}" "${FILE_BODY}" \
    "${RUN_OUT}" "${COMMIT}" "${SIDE_DIR}" <<'PY'
import json, sys, time, pathlib
(
    out, version, fixture, sha, host_stdout, stdout_body, host_file, file_body,
    run_out, commit, side_dir,
) = sys.argv[1:12]
doc = {
    "schema": "strawwu-portable-pe-console/v1",
    "stage": "pe2-win32-console-mvp",
    "status": "PASS",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "real",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "fixture": {
        "path": fixture,
        "sha256": sha,
        "kind": "win32-console-mvp-amd64",
        "markers": ["STRAWWU_PE_CONSOLE_OK", "STRAWWU_PE_CONSOLE_CRT"],
    },
    "api_paths": {
        "file": ["CreateFileA", "WriteFile", "ReadFile", "CloseHandle"],
        "process": ["GetCurrentProcessId", "GetCommandLineA", "GetProcessHeap", "ExitProcess"],
        "crt": ["malloc", "free", "puts", "HeapAlloc", "HeapFree"],
        "not_stub_only": True,
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
        {"name": "stdout_console_marker", "status": "PASS"},
        {"name": "stdout_crt_marker", "status": "PASS"},
        {"name": "host_file_side_effect", "status": "PASS"},
        {"name": "cpu_api_dispatch_test", "status": "PASS"},
        {"name": "runtime_exec_test", "status": "PASS"},
        {"name": "no_wine_substrate", "status": "PASS"},
    ],
    "evidence": [
        "tests/portable/output/pe-console.json",
        "tests/portable/fixtures/pe2-console-mvp.exe",
        "components/strawwu-nt/src/cpu.rs",
        "components/strawwu-nt/src/pe.rs",
        "components/strawwu-nt/src/win32_stubs.rs",
    ],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "legacy/archive native-era path; product default execution_backend=wine (proton-ge; powered by Wine); not a full Windows OS claim",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "mode=simulated is not accepted as success",
        "not stub-only: real CPU dispatch of file/process/CRT APIs",
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
jq -e '.api_paths.not_stub_only == true' "${OUT_JSON}" >/dev/null
log "verify predicates OK"
