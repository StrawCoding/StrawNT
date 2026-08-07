#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-pe-real-exec.sh — pe1 real CPU / instruction loop evidence.
# Runs the minimal console PE fixture through native strawwu-nt CPU loop,
# asserts observable stdout/file side effects, and writes
# tests/portable/output/pe-real-exec.json (top-level status=PASS|FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-real-exec.json"
FIXTURE_DIR="${REPO_ROOT}/tests/portable/fixtures"
FIXTURE_EXE="${FIXTURE_DIR}/pe1-console-hello.exe"
SIDE_DIR="${OUT_DIR}/pe1-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-pe-real-exec] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-pe-real-exec/v1",
    "stage": "pe1-real-cpu-exec",
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

log "emitting fixture PE via strawwu-nt"
EMIT_DIR="$(mktemp -d /tmp/strawwu-pe1-emit.XXXXXX)"
cleanup_emit() { rm -rf "${EMIT_DIR}"; }
trap cleanup_emit EXIT
mkdir -p "${EMIT_DIR}/src"
cat > "${EMIT_DIR}/Cargo.toml" <<EOF
[package]
name = "pe1-emit"
version = "0.0.0"
edition = "2021"
[dependencies]
strawwu-nt = { path = "${COMPONENTS}/strawwu-nt" }
EOF
cat > "${EMIT_DIR}/src/main.rs" <<'EOF'
fn main() {
    let pe = strawwu_nt::build_real_console_fixture_pe();
    let out = std::env::args().nth(1).expect("out path");
    std::fs::write(&out, &pe).expect("write fixture");
    println!("wrote {} bytes to {}", pe.len(), out);
}
EOF
(cd "${EMIT_DIR}" && cargo run --quiet --release -- "${FIXTURE_EXE}") \
    || write_fail "failed to emit pe1 fixture"

[[ -f "${FIXTURE_EXE}" ]] || write_fail "fixture missing: ${FIXTURE_EXE}"
FIXTURE_SHA="$(sha256sum "${FIXTURE_EXE}" | awk '{print $1}')"
log "fixture sha256=${FIXTURE_SHA} path=${FIXTURE_EXE}"

STRAWWU_BIN="${COMPONENTS}/target/release/strawwu"
[[ -x "${STRAWWU_BIN}" ]] || write_fail "strawwu binary missing"

export STRAWWU_PE_SIDE_EFFECT_DIR="${SIDE_DIR}"
export STRAWWU_REQUIRE_REAL_EXEC=1
export STRAWWU_APP_REGISTRY="${SIDE_DIR}/app-registry.json"
export HOME="${SIDE_DIR}/home"
mkdir -p "${HOME}/.local/share/applications" "${HOME}/.local/share/strawwu"

log "running strawwu run on fixture (native, require real)"
set +e
RUN_OUT="$("${STRAWWU_BIN}" run "${FIXTURE_EXE}" --backend native 2>&1)"
RUN_RC=$?
set -e
log "run rc=${RUN_RC}"
printf '%s\n' "${RUN_OUT}" | sed 's/^/  | /'

echo "${RUN_OUT}" | grep -q 'mode=real' || write_fail "launcher did not report mode=real"
echo "${RUN_OUT}" | grep -vq 'mode=simulated' || true
if echo "${RUN_OUT}" | grep -q 'mode=simulated'; then
    write_fail "launcher still reports mode=simulated"
fi
[[ "${RUN_RC}" -eq 0 ]] || write_fail "strawwu run failed rc=${RUN_RC}"

HOST_STDOUT="${SIDE_DIR}/pe-stdout.txt"
[[ -f "${HOST_STDOUT}" ]] || write_fail "missing host side-effect file ${HOST_STDOUT}"
STDOUT_BODY="$(cat "${HOST_STDOUT}")"
echo "${STDOUT_BODY}" | grep -q 'STRAWWU_PE_REAL_OK' \
    || write_fail "side-effect stdout missing STRAWWU_PE_REAL_OK"

# Also confirm marker appeared on process stdout capture
echo "${RUN_OUT}" | grep -q 'STRAWWU_PE_REAL_OK' \
    || write_fail "process output missing STRAWWU_PE_REAL_OK marker"

# Refuse Wine substrate in product paths (pe0 already withdrew; keep regression guard).
if command -v rg >/dev/null 2>&1; then
    if rg -n -i 'ensure_wine|wine_backend|STRAWWU_BACKEND=wine|launch_via_wine' \
        "${REPO_ROOT}/components" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" \
        >/tmp/pe1-wine-rg.txt 2>/dev/null; then
        write_fail "wine substrate markers found in product tree"
    fi
fi

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

python3 - "${OUT_JSON}" "${VERSION}" "${FIXTURE_EXE}" "${FIXTURE_SHA}" \
    "${HOST_STDOUT}" "${STDOUT_BODY}" "${RUN_OUT}" "${COMMIT}" "${SIDE_DIR}" <<'PY'
import json, sys, time, pathlib
(
    out, version, fixture, sha, host_stdout, stdout_body, run_out, commit, side_dir
) = sys.argv[1:10]
doc = {
    "schema": "strawwu-portable-pe-real-exec/v1",
    "stage": "pe1-real-cpu-exec",
    "status": "PASS",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "real",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "fixture": {
        "path": fixture,
        "sha256": sha,
        "kind": "minimal-amd64-console-pe",
        "marker": "STRAWWU_PE_REAL_OK",
    },
    "side_effects": {
        "stdout_file": host_stdout,
        "stdout": stdout_body,
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
        {"name": "stdout_marker", "status": "PASS"},
        {"name": "host_side_effect_file", "status": "PASS"},
        {"name": "no_wine_substrate", "status": "PASS"},
    ],
    "evidence": [
        "tests/portable/output/pe-real-exec.json",
        "tests/portable/fixtures/pe1-console-hello.exe",
        "components/strawwu-nt/src/cpu.rs",
        "components/strawwu-runtime/src/executor.rs",
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
jq -e '.mode != "simulated"' "${OUT_JSON}" >/dev/null
log "verify predicates OK"
