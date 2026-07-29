#!/usr/bin/env bash
# nt1-real-graphics.sh — StrawNT native PE triangle/present evidence.
# Emits tests/strawnt/output/nt1-graphics.json (top-level PASS|FAIL)
# with mode!=simulated, backend=native, and observable side-effect files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt1-graphics.json"
SIDE_DIR="${OUT_DIR}/nt1-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[nt1-real-graphics] $*"; }

mkdir -p "${OUT_DIR}"
rm -rf "${SIDE_DIR}"
mkdir -p "${SIDE_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" "${SIDE_DIR}" <<'PY'
import json, sys, time
out, version, msg, side = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {
    "schema": "strawnt-nt1-graphics/v1",
    "stage": "nt1-real-graphics",
    "product": "StrawNT",
    "status": "FAIL",
    "version": version,
    "mode": "simulated",
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "side_effects": {"dir": side},
    "failures": [msg],
    "claims": {
        "full_windows_compat": false,
        "anticheat_ranked_pass": false,
        "wine_proton_used": false,
        "simulated_ok": false,
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

log "cargo test strawwu-nt cpu gui triangle path"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt cpu_runs_win32_gui_mvp_user32_gdi -- --nocapture) \
    || write_fail "strawwu-nt GUI PE triangle test failed"

log "cargo test strawwu-runtime GUI PE execute"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime execute_win32_gui_mvp_fixture -- --nocapture) \
    || write_fail "strawwu-runtime GUI PE execute test failed"

log "building nt-graphics-verify (release)"
(cd "${COMPONENTS}" && cargo build -p strawwu-runtime --release --bin nt-graphics-verify) \
    || write_fail "cargo build nt-graphics-verify failed"

VERIFY_BIN="${COMPONENTS}/target/release/nt-graphics-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "nt-graphics-verify binary missing"

log "running nt-graphics-verify → ${OUT_JSON}"
"${VERIFY_BIN}" "${OUT_JSON}" "${SIDE_DIR}" 640 480 \
    || write_fail "nt-graphics-verify failed"

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"
[[ -s "${SIDE_DIR}/nt-triangle.ppm" ]] || write_fail "missing nt-triangle.ppm"
[[ -s "${SIDE_DIR}/nt-present.json" ]] || write_fail "missing nt-present.json"

# Hermes verify subset (local gate; final mark still via trigger-verify)
python3 - "${OUT_JSON}" "${SIDE_DIR}" <<'PY' || write_fail "evidence validation failed"
import json, sys
from pathlib import Path
out, side = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(out.read_text(encoding="utf-8"))
assert doc.get("status") == "PASS", f"bad status {doc.get('status')}"
assert doc.get("mode") != "simulated", f"mode must not be simulated: {doc.get('mode')}"
assert doc.get("backend") == "native" or doc.get("execution_backend") == "native"
assert doc.get("claims", {}).get("wine_proton_used") is False
assert doc.get("claims", {}).get("simulated_ok") is False
se = doc.get("side_effects") or {}
f = se.get("present_file") or se.get("triangle_file") or (doc.get("artifacts") or [None])[0]
assert f and Path(f).is_file() and Path(f).stat().st_size > 0, f"side effect missing: {f}"
ppm = side / "nt-triangle.ppm"
data = ppm.read_bytes()
assert data.startswith(b"P6"), "ppm not P6"
tri = doc.get("triangle") or {}
assert int(tri.get("pixels") or 0) > 100, "triangle pixels missing"
present = doc.get("present") or {}
assert int(present.get("frames") or 0) >= 1, "present frames missing"
print(f"ok status=PASS mode={doc.get('mode')} pixels={tri.get('pixels')} present={present.get('frames')}")
PY

# Wine/Proton must not be substrate
if grep -qiE 'wine|proton' "${OUT_JSON}"; then
    python3 - "${OUT_JSON}" <<'PY' || write_fail "evidence mentions wine/proton incorrectly"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("claims", {}).get("wine_proton_used") is False
assert doc.get("backend") == "native"
print("wine denial ok")
PY
fi

log "nt1-real-graphics PASS evidence ready: ${OUT_JSON}"
jq -r '.status + " mode=" + (.mode|tostring) + " version=" + (.version|tostring) + " pixels=" + (.triangle.pixels|tostring)' "${OUT_JSON}"
