#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# nt4-anticheat-honest.sh — StrawNT EAC/BattlEye/Vanguard honesty matrix.
# Emits tests/strawnt/output/nt4-anticheat.json with top-level PARTIAL|PASS|FAIL.
#
# Real StrawNT surface-probe PEs + ProbeEngine + bridge PolicySet side effects.
# Honest grades A/B/C/F (anti-cheat cap ≤B; Vanguard=F). Never claims ranked
# play or official AC signature pass. No Wine/Proton.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt4-anticheat.json"
SIDE_DIR="${OUT_DIR}/nt4-side-effects"
FIXTURE_DIR="${REPO_ROOT}/tests/strawnt/fixtures/anticheat"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[nt4-anticheat-honest] $*"; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}"
rm -rf "${SIDE_DIR}"
mkdir -p "${SIDE_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" "${SIDE_DIR}" <<'PY'
import json, sys, time
out, version, msg, side = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {
    "schema": "strawnt-nt4-anticheat/v1",
    "stage": "nt4-anticheat-honest",
    "product": "StrawNT",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "real_binaries": False,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "cases": [],
    "results": [],
    "side_effects": {"dir": side},
    "failures": [msg],
    "claims": {
        "real_binaries": False,
        "wine_proton_used": False,
        "native_pe_backend": True,
        "anti_cheat_claimed": False,
        "ranked_pass_claimed": False,
        "anticheat_ranked_pass": False,
        "aaa_claimed": False,
        "full_windows_compat": False,
        "simulated_ok": False,
        "official_ac_signature_pass": False,
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

log "cargo test strawwu-anticheat"
(cd "${COMPONENTS}" && cargo test -p strawwu-anticheat -- --nocapture) \
    || write_fail "strawwu-anticheat cargo tests failed"

log "cargo test strawwu-nt anticheat probe PE parse"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt win32_anticheat_probe_fixtures_parse_as_amd64_cui -- --nocapture) \
    || write_fail "strawwu-nt anticheat probe parse test failed"

log "building nt-anticheat-verify (release)"
(cd "${COMPONENTS}" && cargo build -p strawwu-runtime --release --bin nt-anticheat-verify) \
    || write_fail "cargo build nt-anticheat-verify failed"

VERIFY_BIN="${COMPONENTS}/target/release/nt-anticheat-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "nt-anticheat-verify binary missing"

log "running nt-anticheat-verify → ${OUT_JSON}"
"${VERIFY_BIN}" "${OUT_JSON}" "${SIDE_DIR}" "${FIXTURE_DIR}" \
    || write_fail "nt-anticheat-verify failed"

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"
[[ -f "${FIXTURE_DIR}/nt4-eac-probe.exe" ]] || write_fail "missing eac probe fixture"
[[ -d "${SIDE_DIR}/eac_driver_probe" ]] || write_fail "missing eac side-effects"

# Hermes verify subset (local gate; final mark still via trigger-verify)
python3 - "${OUT_JSON}" "${SIDE_DIR}" <<'PY' || write_fail "evidence validation failed"
import json, sys
from pathlib import Path
out, side = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(out.read_text(encoding="utf-8"))
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status={status}"
cases = doc.get("cases") or []
results = doc.get("results") or []
assert len(cases) >= 1 or len(results) >= 1, "need ≥1 case/result"
assert len(cases) >= 4, f"expected ≥4 AC cases, got {len(cases)}"
claims = doc.get("claims") or {}
assert claims.get("ranked_pass_claimed") is False
assert claims.get("anticheat_ranked_pass") is False
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("anti_cheat_claimed") is False
assert claims.get("aaa_claimed") is False
assert claims.get("official_ac_signature_pass") is False
# NTW0 soft-reset: execution_backend native assert retired as product gate
assert doc.get("real_binaries") is True or claims.get("real_binaries") is True

required = {"eac_driver_probe", "battleye_init", "vanguard_tpm_probe", "custom_ac_window_process"}
present = {c.get("name") for c in cases}
missing = sorted(required - present)
assert not missing, f"missing required cases: {missing}"

real_pe = 0
for row in cases:
    assert row.get("status") in ("PARTIAL", "FAIL"), f"dishonest status for {row.get('name')}"
    assert row.get("grade") in ("A", "B", "C", "F"), f"bad grade for {row.get('name')}"
    assert row.get("grade") != "A", f"anticheat must not claim Hub A (可玩): {row.get('name')}"
    assert row.get("substantive_verified") is True
    assert row.get("bridge_policy_side_effect") is True
    if row.get("real_probe_pe") is True:
        real_pe += 1
        pe = row.get("pe") or {}
        assert pe.get("mode") == "real", f"{row.get('name')} pe.mode != real"
        se = pe.get("side_effects") or {}
        marker = se.get("marker_file")
        assert marker and Path(marker).is_file(), f"missing marker {marker}"
        logf = se.get("log_file")
        assert logf and Path(logf).is_file(), f"missing log {logf}"

assert real_pe >= 1, f"need ≥1 real probe PE, got {real_pe}"

vg = next(c for c in cases if c["name"] == "vanguard_tpm_probe")
assert vg["grade"] == "F", "Vanguard must remain grade F"
assert vg.get("real_probe_pe") is not True, "must not claim real vendor Vanguard PE"

# Top-level must never claim ranked PASS
assert status != "PASS" or claims.get("ranked_pass_claimed") is False
# Honesty: overall PASS forbidden for anticheat matrix in this stage
assert status == "PARTIAL", f"anticheat honesty matrix must be PARTIAL, got {status}"

print(
    f"ok status={status} cases={len(cases)} real_pe={real_pe} "
    f"grades={doc.get('summary', {}).get('grades_present')}"
)
PY

log "ensure no wine/proton or ranked claim"
python3 - "${OUT_JSON}" <<'PY' || write_fail "honesty claim invalid"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("ranked_pass_claimed") is False
assert (claims.get("ranked_pass_claimed") or False) is False
print("wine/proton + ranked denial: ok")
PY

log "nt4 anticheat evidence ready: ${OUT_JSON}"
jq -r '"status=" + .status + " version=" + (.version|tostring) + " cases=" + ((.cases|length)|tostring) + " ranked_pass_claimed=" + ((.claims.ranked_pass_claimed // false)|tostring)' "${OUT_JSON}"
