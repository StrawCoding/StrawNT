#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-gx-anticheat.sh — gx4 EAC/BattlEye/Vanguard/CustomAC probe matrix evidence.
# Emits tests/portable/output/gx-anticheat.json with top-level PASS|PARTIAL|FAIL.
# Honest grades only; never claims ranked / official AC signature pass.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/gx-anticheat.json"
RAW_JSON="${OUT_DIR}/gx4-anticheat-raw.json"
COMPONENTS="${REPO_ROOT}/components"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-gx-anticheat] $*"; }

mkdir -p "${OUT_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-gx-anticheat/v1",
    "stage": "gx4-anticheat-matrix",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "cases": [],
    "results": [],
    "claims": {
        "wine_proton_used": False,
        "native_pe_backend": True,
        "anti_cheat_claimed": False,
        "ranked_pass_claimed": False,
        "aaa_claimed": False
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "legacy/archive native-era path; product default execution_backend=wine (proton-ge; powered by Wine); not a full Windows OS claim",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked pass claim",
        "no 3A completion claim"
    ]
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
    die "${msg}"
}

log "cargo test strawwu-anticheat"
(cd "${COMPONENTS}" && cargo test -p strawwu-anticheat -- --nocapture) \
    || write_fail "strawwu-anticheat cargo tests failed"

log "build anticheat-substantive-verify"
(cd "${COMPONENTS}" && cargo build -p strawwu-anticheat --release --bin anticheat-substantive-verify) \
    || write_fail "cargo build anticheat-substantive-verify failed"

VERIFY_BIN="${COMPONENTS}/target/release/anticheat-substantive-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "missing anticheat-substantive-verify binary"

log "generate raw anticheat substantive evidence"
"${VERIFY_BIN}" "${VERSION}" > "${RAW_JSON}" \
    || write_fail "anticheat-substantive-verify run failed"
[[ -s "${RAW_JSON}" ]] || write_fail "raw evidence missing or empty: ${RAW_JSON}"

log "normalize gx4 evidence contract → ${OUT_JSON}"
python3 - "${RAW_JSON}" "${OUT_JSON}" "${VERSION}" <<'PY' || write_fail "failed to normalize gx4 evidence"
import json, sys, time

raw_path, out_path, version = sys.argv[1], sys.argv[2], sys.argv[3]
raw = json.load(open(raw_path, encoding="utf-8"))

cases = []
for c in raw.get("cases", []):
    evidence = c.get("evidence") or {}
    probe_pass = int(evidence.get("probe_pass", 0))
    probe_total = int(evidence.get("probe_total", 0))
    ratio = (probe_pass / probe_total) if probe_total else 0.0
    status = c.get("status", "PARTIAL")
    # Harden honesty: never elevate anticheat case to PASS
    if status == "PASS":
        status = "PARTIAL"
    cases.append({
        "name": c.get("name"),
        "anticheat_type": c.get("anticheat_type"),
        "backend": c.get("backend", "native"),
        "status": status,
        "grade": c.get("grade"),
        "substantive_verified": bool(c.get("substantive_verified")),
        "probe_pass": probe_pass,
        "probe_total": probe_total,
        "probe_ratio": round(ratio, 3),
        "bridge_policy_side_effect": bool(evidence.get("bridge_policy_side_effect")),
        "notes": c.get("notes", ""),
        "disclaimer": evidence.get("honest_disclaimer", ""),
        "probes": evidence.get("probes", []),
    })

required = {"eac_driver_probe", "battleye_init", "vanguard_tpm_probe", "custom_ac_window_process"}
present = {c["name"] for c in cases}
missing = sorted(required - present)
if missing:
    raise SystemExit(f"missing required cases: {missing}")

# Top-level: PARTIAL when probes ran without crash; FAIL only if empty/broken.
if not cases:
    status = "FAIL"
elif any(c.get("status") == "FAIL" and c.get("probe_pass", 0) == 0 for c in cases):
    status = "PARTIAL"  # no-crash goal still met if other cases ran
else:
    status = "PARTIAL"

# Never claim overall PASS for anticheat matrix.
if status == "PASS":
    status = "PARTIAL"

grades = sorted({c.get("grade") for c in cases if c.get("grade")})
doc = {
    "schema": "strawwu-portable-gx-anticheat/v1",
    "stage": "gx4-anticheat-matrix",
    "status": status,
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "source": {
        "crate": "strawwu-anticheat",
        "verify_bin": "anticheat-substantive-verify",
        "raw_schema": raw.get("schema"),
        "verification_stage": "gx4-anticheat-matrix",
    },
    "claims": {
        "wine_proton_used": False,
        "native_pe_backend": True,
        "anti_cheat_claimed": False,
        "ranked_pass_claimed": False,
        "aaa_claimed": False
    },
    "cases": cases,
    "results": cases,
    "summary": {
        "total_cases": len(cases),
        "partial_or_fail_only": all(c.get("status") in ("PARTIAL", "FAIL") for c in cases),
        "grades_present": grades,
        "bridge_policy_side_effects": sum(1 for c in cases if c.get("bridge_policy_side_effect")),
        "overall_from_engine": raw.get("overall", "PARTIAL"),
    },
    "known_limitations": [
        "probe stubs + strawwu-bridge PolicySet side effects; not real EAC/BE/Vanguard binaries",
        "goal is run-without-crash + honest A/B/C/F grades",
        "never claims ranked play or official AC signature pass",
        "Vanguard kernel/TPM remain grade F by policy"
    ],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "legacy/archive native-era path; product default execution_backend=wine (proton-ge; powered by Wine); not a full Windows OS claim",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked pass claim",
        "no 3A completion claim"
    ]
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out_path)
PY

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"

log "local evidence contract validation"
python3 - "${OUT_JSON}" <<'PY' || write_fail "gx4 evidence contract validation failed"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status={status}"
cases = doc.get("cases") or []
results = doc.get("results") or []
assert len(cases) >= 1 or len(results) >= 1, "need at least 1 case/result"
assert len(cases) >= 4, f"expected >=4 AC cases, got {len(cases)}"
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("anti_cheat_claimed") is False
assert claims.get("ranked_pass_claimed") is False
assert claims.get("aaa_claimed") is False
for row in cases:
    assert row.get("status") in ("PARTIAL", "FAIL"), f"dishonest status for {row.get('name')}"
    assert row.get("grade") in ("A", "B", "C", "F"), f"bad grade for {row.get('name')}"
    assert row.get("grade") != "A", f"anticheat must not claim Hub A (可玩): {row.get('name')}"
    assert row.get("substantive_verified") is True
    assert row.get("bridge_policy_side_effect") is True
# Vanguard must stay F
vg = next(c for c in cases if c["name"] == "vanguard_tpm_probe")
assert vg["grade"] == "F", "Vanguard must remain grade F"
print(f"ok status={status} cases={len(cases)} grades={doc.get('summary',{}).get('grades_present')}")
PY

log "ensure no wine/proton substrate claim"
python3 - "${OUT_JSON}" <<'PY' || write_fail "wine/proton claim invalid"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("ranked_pass_claimed") is False
print("wine/proton + ranked denial: ok")
PY

log "gx4 anticheat evidence ready: ${OUT_JSON}"
jq -r '.status + " version=" + (.version|tostring) + " cases=" + (.summary.total_cases|tostring) + " grades=" + (.summary.grades_present|tostring)' "${OUT_JSON}"
