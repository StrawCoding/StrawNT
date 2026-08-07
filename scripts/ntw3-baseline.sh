#!/usr/bin/env bash
# ntw3-baseline.sh — NTW3 optimization baseline harness (cold start / RSS / prefix create).
# Honesty: numeric metrics only; never simulated top-level PASS.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw3-baseline.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/strawnt-ntw3-base.XXXXXX")"
export STRAWNT_HOME="${WORK}/home"
export STRAWNT_ROOT="${REPO_ROOT}"
export STRAWNT_FORCE_XVFB=1
# Authoritative plan (NTW3 Task 7): RSS after 60s idle minimum.
# Override may raise the window; values below 60 are clamped upward.
export STRAWNT_NTW3_IDLE_SEC="${STRAWNT_NTW3_IDLE_SEC:-60}"
if [[ "${STRAWNT_NTW3_IDLE_SEC}" -lt 60 ]]; then
  echo "STRAWNT_NTW3_IDLE_SEC=${STRAWNT_NTW3_IDLE_SEC} < 60; clamping to 60" >&2
  export STRAWNT_NTW3_IDLE_SEC=60
fi
mkdir -p "${OUT_DIR}" "${STRAWNT_HOME}"

cleanup() {
  if [[ -d "${STRAWNT_HOME}" ]]; then
    find "${STRAWNT_HOME}" -type d -name 'drive_c' -printf '%h\n' 2>/dev/null | while read -r p; do
      WINEPREFIX="${p}" \
        "${REPO_ROOT}/third_party/proton-ge/dist/files/bin/wineserver" -k 2>/dev/null || true
    done
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
GIT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

echo "== build strawwu-launcher =="
(cd "${REPO_ROOT}/components" && cargo build -p strawwu-launcher -q)
STRAWNT_BIN="${REPO_ROOT}/components/target/debug/strawnt"
[[ -x "${STRAWNT_BIN}" ]] || { echo "strawnt binary missing" >&2; exit 1; }

echo "== strawnt bench --profile baseline =="
RAW="${WORK}/baseline-raw.json"
"${STRAWNT_BIN}" bench --profile baseline --json --home "${STRAWNT_HOME}" | tee "${RAW}"

# Wrap with stage envelope expected by Hermes verify.
jq -n \
  --arg schema "strawnt-ntw3-baseline/v1" \
  --arg stage "ntw3-optimize" \
  --arg product "StrawNT" \
  --arg version "${VERSION}" \
  --arg generated_at "${TS}" \
  --arg git_head "${GIT_HEAD}" \
  --slurpfile raw "${RAW}" \
  '
  ($raw[0]) as $b
  | {
      schema: $schema,
      stage: $stage,
      status: ($b.status // "FAIL"),
      product: $product,
      version: $version,
      generated_at: $generated_at,
      git_head: $git_head,
      profile: "baseline",
      execution_backend: "wine",
      backend: "wine",
      engine: ($b.engine // "proton-ge"),
      pin: ($b.pin // $b.engine_pin // ""),
      engine_pin: ($b.engine_pin // $b.pin // ""),
      powered_by: "Wine",
      powered_by_wine: true,
      simulated: false,
      metrics: ($b.metrics // null),
      bench: $b,
      claims: {
        measurable: true,
        powered_by_wine: true,
        full_windows_claimed: false,
        ranked_anticheat_claimed: false,
        simulated: false
      },
      artifacts: {
        schema: "tests/strawnt/bench_schema.json",
        harness: "scripts/ntw3-baseline.sh"
      }
    }
  ' > "${OUT_JSON}"

echo "Wrote ${OUT_JSON}"
jq -e '.metrics.cold_start_ms != null and .metrics.prefix_create_ms != null' "${OUT_JSON}" >/dev/null
jq -e '.metrics.rss_after_idle_kb != null and (.metrics.rss_idle_sec // 0) >= 60' "${OUT_JSON}" >/dev/null
jq -e '.claims.measurable == true' "${OUT_JSON}" >/dev/null
echo "ntw3-baseline: $(jq -r .status "${OUT_JSON}") idle=${STRAWNT_NTW3_IDLE_SEC}s"
