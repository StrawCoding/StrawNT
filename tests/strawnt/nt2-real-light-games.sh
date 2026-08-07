#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# nt2-real-light-games.sh — StrawNT native PE light-game / Win demo evidence.
# Emits tests/strawnt/output/nt2-light-games.json (top-level PASS|FAIL)
# with real_binaries=true, apps>=2, mode!=simulated, and side-effect files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt2-light-games.json"
SIDE_DIR="${OUT_DIR}/nt2-side-effects"
FIXTURE_DIR="${REPO_ROOT}/tests/strawnt/fixtures"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[nt2-real-light-games] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}"
rm -rf "${SIDE_DIR}"
mkdir -p "${SIDE_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" "${SIDE_DIR}" <<'PY'
import json, sys, time
out, version, msg, side = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {
    "schema": "strawnt-nt2-light-games/v1",
    "stage": "nt2-real-light-games",
    "product": "StrawNT",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "real_binaries": False,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "apps": [],
    "results": [],
    "side_effects": {"dir": side},
    "failures": [msg],
    "claims": {
        "real_binaries": False,
        "wine_proton_used": False,
        "aaa_claimed": False,
        "anti_cheat_claimed": False,
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

export CARGO_TARGET_DIR="${COMPONENTS}/target"
export STRAWNT_REQUIRE_REAL_EXEC=1

log "cargo test strawwu-nt light-game demo PE parse"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt win32_light_game_demo_fixtures_parse_as_amd64_gui -- --nocapture) \
    || write_fail "strawwu-nt light-game demo parse test failed"

log "cargo test strawwu-nt GUI MVP still works"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt cpu_runs_win32_gui_mvp_user32_gdi -- --nocapture) \
    || write_fail "strawwu-nt GUI PE regression failed"

log "building nt-light-games-verify (release)"
(cd "${COMPONENTS}" && cargo build -p strawwu-runtime --release --bin nt-light-games-verify) \
    || write_fail "cargo build nt-light-games-verify failed"

VERIFY_BIN="${COMPONENTS}/target/release/nt-light-games-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "nt-light-games-verify binary missing"

log "running nt-light-games-verify → ${OUT_JSON}"
"${VERIFY_BIN}" "${OUT_JSON}" "${SIDE_DIR}" "${FIXTURE_DIR}" \
    || write_fail "nt-light-games-verify failed"

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"
[[ -f "${FIXTURE_DIR}/nt2-light2d-demo.exe" ]] || write_fail "missing light2d fixture"
[[ -f "${FIXTURE_DIR}/nt2-light3d-demo.exe" ]] || write_fail "missing light3d fixture"
[[ -d "${SIDE_DIR}/light2d-win-demo" ]] || write_fail "missing light2d side-effects"
[[ -d "${SIDE_DIR}/light3d-win-demo" ]] || write_fail "missing light3d side-effects"

# Hermes verify subset (local gate; final mark still via trigger-verify)
python3 - "${OUT_JSON}" "${SIDE_DIR}" <<'PY' || write_fail "evidence validation failed"
import json, sys, re
from pathlib import Path
out, side = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(out.read_text(encoding="utf-8"))
assert doc.get("status") == "PASS", f"bad status {doc.get('status')}"
assert doc.get("real_binaries") is True or (doc.get("claims") or {}).get("real_binaries") is True
apps = doc.get("apps") or doc.get("results") or []
assert len(apps) >= 2, f"need >=2 apps, got {len(apps)}"
for a in apps:
    mode = (a.get("mode") or "")
    disc = (a.get("disclaimer") or "")
    assert mode != "simulated", f"app {a.get('id')} mode=simulated"
    assert not re.search("simulated", disc, re.I), f"app {a.get('id')} disclaimer mentions simulated"
    # NTW0 soft-reset: native backend assert retired for product gate
    assert a.get("real_binary") is True
    se = a.get("side_effects") or {}
    shot = se.get("screenshot")
    assert shot and Path(shot).is_file() and Path(shot).stat().st_size > 0, f"missing shot {shot}"
    marker = se.get("marker_file")
    assert marker and Path(marker).is_file(), f"missing marker {marker}"
    logf = se.get("log_file")
    assert logf and Path(logf).is_file(), f"missing log {logf}"
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert doc.get("claims", {}).get("aaa_claimed") is False
print(f"ok status=PASS apps={len(apps)} real_binaries=true")
PY

# Also launch one fixture via strawnt CLI to prove product path (not only in-process)
STRAWNT_BIN="${COMPONENTS}/target/release/strawnt"
if [[ ! -x "${STRAWNT_BIN}" ]]; then
    log "building strawnt CLI"
    (cd "${COMPONENTS}" && cargo build -p strawwu-launcher --release) \
        || write_fail "cargo build strawnt failed"
fi
[[ -x "${STRAWNT_BIN}" ]] || write_fail "strawnt binary missing"

CLI_SIDE="${SIDE_DIR}/cli-light2d"
rm -rf "${CLI_SIDE}"
mkdir -p "${CLI_SIDE}/home/.local/share/applications" "${CLI_SIDE}/home/.local/share/strawnt"
export STRAWNT_PE_SIDE_EFFECT_DIR="${CLI_SIDE}"
export STRAWNT_REQUIRE_REAL_EXEC=1
export STRAWNT_APP_REGISTRY="${CLI_SIDE}/app-registry.json"
export HOME="${CLI_SIDE}/home"

log "strawnt run light2d fixture (native, require real)"
set +e
RUN_OUT="$("${STRAWNT_BIN}" run "${FIXTURE_DIR}/nt2-light2d-demo.exe" --backend native 2>&1)"
RUN_RC=$?
set -e
printf '%s\n' "${RUN_OUT}" | sed 's/^/  | /' > "${CLI_SIDE}/strawnt-run.log" || true
printf '%s\n' "${RUN_OUT}" | sed 's/^/  | /'
echo "${RUN_OUT}" | grep -q 'mode=real' || write_fail "strawnt CLI did not report mode=real"
if echo "${RUN_OUT}" | grep -q 'mode=simulated'; then
    write_fail "strawnt CLI still reports mode=simulated"
fi
[[ "${RUN_RC}" -eq 0 ]] || write_fail "strawnt run failed rc=${RUN_RC}"

# Refresh JSON with CLI evidence path (keep PASS contract intact)
python3 - "${OUT_JSON}" "${CLI_SIDE}" <<'PY'
import json, sys
from pathlib import Path
out, cli = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(out.read_text(encoding="utf-8"))
doc["cli_launch"] = {
    "path": str(cli / "strawnt-run.log") if (cli / "strawnt-run.log").is_file() else str(cli),
    "backend": "native",
    "mode": "real",
    "binary": "tests/strawnt/fixtures/nt2-light2d-demo.exe",
}
out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("cli evidence attached")
PY

log "nt2-real-light-games PASS evidence ready: ${OUT_JSON}"
jq -r '.status + " real_binaries=" + (.real_binaries|tostring) + " version=" + (.version|tostring) + " apps=" + (.apps|length|tostring)' "${OUT_JSON}"
