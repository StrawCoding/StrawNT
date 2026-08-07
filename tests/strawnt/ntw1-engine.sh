#!/usr/bin/env bash
# ntw1-engine.sh — NTW1 Proton-GE vendor + engine smoke evidence.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw1-engine.json"
mkdir -p "${OUT_DIR}"

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
GIT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

failures=()
fail() { failures+=("$*"); }

require_file() {
    local rel="$1"
    if [[ ! -f "${REPO_ROOT}/${rel}" ]]; then
        fail "missing ${rel}"
    fi
}

require_file "third_party/proton-ge/PIN"
require_file "third_party/proton-ge/README.md"
require_file "scripts/fetch-proton-ge.sh"
require_file "scripts/verify-proton-ge.sh"
require_file "components/strawnt-engine/src/lib.rs"
require_file ".gitattributes"

load_pin() {
  local pin_file="$1"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    if [[ "${line}" =~ ^([a-z_][a-z0-9_]*)=(.*)$ ]]; then
      printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
    fi
  done < "${pin_file}"
}

load_pin "${REPO_ROOT}/third_party/proton-ge/PIN"
PIN_TAG="${tag:-}"
[[ -n "${PIN_TAG}" ]] || fail "PIN tag empty"

if ! bash "${REPO_ROOT}/scripts/verify-proton-ge.sh"; then
    fail "verify-proton-ge.sh non-zero"
fi

export STRAWNT_ROOT="${REPO_ROOT}"
(cd "${REPO_ROOT}/components" && cargo build -p strawwu-launcher -q) || fail "cargo build strawwu-launcher failed"
STRAWNT_BIN="${REPO_ROOT}/components/target/debug/strawnt"
[[ -x "${STRAWNT_BIN}" ]] || fail "strawnt binary missing after build"

ENGINE_JSON="$("${STRAWNT_BIN}" engine status --json 2>/dev/null || true)"
if [[ -z "${ENGINE_JSON}" ]]; then
    fail "strawnt engine status --json empty"
else
    echo "${ENGINE_JSON}" | jq -e '.backend == "wine"' >/dev/null 2>&1 || fail "engine status backend != wine"
    echo "${ENGINE_JSON}" | jq -e --arg p "${PIN_TAG}" '.pin == $p or .engine_pin == $p' >/dev/null 2>&1 \
        || fail "engine status pin mismatch"
fi

DOCTOR_JSON="$("${STRAWNT_BIN}" doctor --json 2>/dev/null || true)"
if [[ -z "${DOCTOR_JSON}" ]]; then
    fail "strawnt doctor --json empty"
else
    echo "${DOCTOR_JSON}" | jq -e '.wine.found == true' >/dev/null 2>&1 || fail "doctor wine.found != true"
    echo "${DOCTOR_JSON}" | jq -e '.powered_by_wine == true or .powered_by == "Wine"' >/dev/null 2>&1 \
        || fail "doctor missing powered by Wine"
fi

(cd "${REPO_ROOT}/components" && cargo test -p strawnt-engine pin_roundtrip_from_repo -q) \
    || fail "strawnt-engine pin unit test failed"

HELLO_JSON="$("${STRAWNT_BIN}" engine hello --json 2>/dev/null || true)"
HELLO_STATUS="FAIL"
CMD_STATUS="FAIL"
MARKER=""
WINE_BIN="${REPO_ROOT}/third_party/proton-ge/dist/${dist_wine_relpath:-files/bin/wine}"
if [[ -z "${HELLO_JSON}" ]]; then
    fail "strawnt engine hello --json empty"
else
    HELLO_STATUS="$(echo "${HELLO_JSON}" | jq -r '.status // "FAIL"')"
    CMD_STATUS="${HELLO_STATUS}"
    MARKER="$(echo "${HELLO_JSON}" | jq -r '.marker // empty')"
    echo "${HELLO_JSON}" | jq -e '.backend == "wine"' >/dev/null 2>&1 || fail "hello backend != wine"
    echo "${HELLO_JSON}" | jq -e --arg p "${PIN_TAG}" '.pin == $p' >/dev/null 2>&1 || fail "hello pin mismatch"
    if [[ "${HELLO_STATUS}" != "PASS" ]]; then
        fail "engine hello status != PASS"
    fi
    echo "${HELLO_JSON}" > "${OUT_DIR}/ntw1-hello.json"
    echo "${HELLO_JSON}" | jq -r '.stdout // empty' > "${OUT_DIR}/ntw1-hello.txt"
fi

[[ -x "${WINE_BIN}" ]] || fail "vendored wine missing: ${WINE_BIN}"

OVERALL="PASS"
if [[ ${#failures[@]} -gt 0 ]] || [[ "${HELLO_STATUS}" != "PASS" ]]; then
    OVERALL="FAIL"
fi

if [[ ${#failures[@]} -eq 0 ]]; then
    FAILURES_JSON='[]'
else
    FAILURES_JSON="$(printf '%s\n' "${failures[@]}" | jq -R . | jq -s .)"
fi

jq -n \
    --arg schema "strawnt-ntw1-engine/v1" \
    --arg stage "ntw1-vendor-engine" \
    --arg status "${OVERALL}" \
    --arg product "StrawNT" \
    --arg version "${VERSION}" \
    --arg generated_at "${TS}" \
    --arg git_head "${GIT_HEAD}" \
    --arg backend "wine" \
    --arg execution_backend "wine" \
    --arg engine "proton-ge" \
    --arg pin "${PIN_TAG}" \
    --arg engine_pin "${PIN_TAG}" \
    --arg hello "${HELLO_STATUS}" \
    --arg cmd "${CMD_STATUS}" \
    --argjson failures "${FAILURES_JSON}" \
    --arg wine_bin "${WINE_BIN}" \
    --arg marker "${MARKER}" \
    '{
        schema: $schema,
        stage: $stage,
        status: $status,
        product: $product,
        version: $version,
        generated_at: $generated_at,
        git_head: $git_head,
        backend: $backend,
        execution_backend: $execution_backend,
        engine: $engine,
        pin: $pin,
        engine_pin: $engine_pin,
        hello: $hello,
        cmd: $cmd,
        claims: {
            pin: $pin,
            engine: $engine,
            backend: $backend,
            powered_by_wine: true,
            distribution: "git-lfs",
            full_windows_claimed: false,
            all_games_playable_claimed: false,
            ranked_anticheat_claimed: false
        },
        artifacts: {
            pin: "third_party/proton-ge/PIN",
            readme: "third_party/proton-ge/README.md",
            fetch: "scripts/fetch-proton-ge.sh",
            verify: "scripts/verify-proton-ge.sh",
            engine_crate: "components/strawnt-engine/",
            wine_bin: $wine_bin,
            hello_stdout: "tests/strawnt/output/ntw1-hello.txt"
        },
        smoke: {
            hello_marker: $marker,
            hello_status: $hello,
            cmd_status: $cmd,
            engine_status_json_ok: true,
            doctor_json_ok: true
        },
        failures: $failures
    }' > "${OUT_JSON}"

echo "ntw1-engine: wrote ${OUT_JSON} status=${OVERALL}"
if [[ "${OVERALL}" != "PASS" ]]; then
    printf '  - %s\n' "${failures[@]}"
    exit 1
fi
jq -e '.status == "PASS"' "${OUT_JSON}" >/dev/null
jq -e '.backend == "wine" or .execution_backend == "wine"' "${OUT_JSON}" >/dev/null
jq -e '(.pin // .engine_pin // .claims.pin) != null and ((.pin // .engine_pin // .claims.pin)|tostring|length) > 0' "${OUT_JSON}" >/dev/null
echo "ntw1-engine: PASS"
