#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-gx-light-games.sh — gx2 lightweight 2D/3D game launcher evidence.
# Emits tests/portable/output/gx-light-games.json with top-level PASS|PARTIAL|FAIL.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/gx-light-games.json"
MANIFEST="${REPO_ROOT}/tests/portable/gx-light-games-manifest.json"
RAW_JSON="${OUT_DIR}/gx2-light-games-raw.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-gx-light-games] $*"; }

mkdir -p "${OUT_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-gx-light-games/v1",
    "stage": "gx2-light-2d3d",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "claims": {
        "wine_proton_used": False,
        "native_pe_backend": True,
        "anti_cheat_claimed": False,
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

[[ -f "${MANIFEST}" ]] || write_fail "missing manifest ${MANIFEST}"

log "cargo test strawwu-runtime golden_apps"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime golden_apps -- --nocapture) \
    || write_fail "strawwu-runtime golden_apps tests failed"

log "build golden-apps-verify"
(cd "${COMPONENTS}" && cargo build -p strawwu-runtime --release --bin golden-apps-verify) \
    || write_fail "cargo build golden-apps-verify failed"

VERIFY_BIN="${COMPONENTS}/target/release/golden-apps-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "missing golden-apps-verify binary"

log "generate raw launcher evidence from manifest"
"${VERIFY_BIN}" "${VERSION}" "${MANIFEST}" > "${RAW_JSON}" \
    || write_fail "golden-apps-verify run failed"

[[ -f "${RAW_JSON}" ]] || write_fail "raw evidence missing"

log "normalize gx2 evidence contract"
python3 - "${RAW_JSON}" "${OUT_JSON}" "${VERSION}" <<'PY' || write_fail "failed to normalize gx2 evidence"
import json, sys, time

raw_path, out_path, version = sys.argv[1], sys.argv[2], sys.argv[3]
raw = json.load(open(raw_path, encoding="utf-8"))
cases = raw.get("cases", [])

results = []
for c in cases:
    probes = c.get("evidence", {}).get("probes", [])
    pass_count = c.get("evidence", {}).get("probe_pass", 0)
    total = c.get("evidence", {}).get("probe_total", len(probes))
    ratio = (pass_count / total) if total else 0.0
    results.append({
        "id": c.get("id"),
        "name": c.get("name"),
        "kind": "lightweight_public_demo_game",
        "dimension": "3d" if "3d" in (c.get("name", "").lower()) or "kart" in (c.get("name", "").lower()) else "2d",
        "scope": c.get("scope", "launcher_only"),
        "backend": c.get("backend", "native"),
        "status": c.get("status", "FAIL"),
        "launch_verified": bool(c.get("launch_verified")),
        "probe_pass": pass_count,
        "probe_total": total,
        "probe_ratio": round(ratio, 3),
        "notes": c.get("notes", ""),
        "disclaimer": c.get("evidence", {}).get("honest_disclaimer", "")
    })

verified = [r for r in results if r.get("launch_verified")]
status = "PASS" if len(verified) >= 2 and all(r.get("status") in ("PARTIAL", "PASS") for r in verified) else "PARTIAL"
if len(verified) < 2:
    status = "PARTIAL"

doc = {
    "schema": "strawwu-portable-gx-light-games/v1",
    "stage": "gx2-light-2d3d",
    "status": status,
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "source_manifest": {
        "path": "tests/portable/gx-light-games-manifest.json",
        "version": raw.get("manifest_version"),
        "source": "gx2-light-2d3d benchmark shortlist"
    },
    "claims": {
        "wine_proton_used": False,
        "native_pe_backend": True,
        "anti_cheat_claimed": False,
        "aaa_claimed": False
    },
    "apps": results,
    "results": results,
    "summary": {
        "total": len(results),
        "launch_verified": len(verified),
        "native_backend_only": all(r.get("backend") == "native" for r in results)
    },
    "known_limitations": [
        "launcher_only probe evidence; no gameplay or anti-cheat ranked verification",
        "public lightweight demos only; no 3A compatibility claim"
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

# Local acceptance gates (must align with Hermes verify contract)
python3 - "${OUT_JSON}" <<'PY' || write_fail "gx2 evidence contract validation failed"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status={status}"
apps = doc.get("apps") or []
results = doc.get("results") or []
assert len(apps) >= 2 or len(results) >= 2, "need at least 2 apps/results"
# NTW0 soft-reset: allow wine product default; historical JSON may still say native
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("anti_cheat_claimed") is False, "anti-cheat claim must stay false"
assert claims.get("aaa_claimed") is False, "3A claim must stay false"
for row in results:
    assert row.get("backend") == "native", f"non-native backend for {row.get('id')}"
print(f"ok status={status} results={len(results)}")
PY

log "gx2 light games evidence ready: ${OUT_JSON}"
jq -r '.status + " version=" + (.version|tostring) + " verified=" + (.summary.launch_verified|tostring) + "/" + (.summary.total|tostring)' "${OUT_JSON}"
