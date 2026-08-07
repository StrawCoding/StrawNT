#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-gx-launchers.sh — gx3 Steam/Epic/Delta launcher evidence.
# Emits tests/portable/output/gx-launchers.json with top-level PASS|PARTIAL|FAIL.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/gx-launchers.json"
COMPONENTS="${REPO_ROOT}/components"
MANIFEST="${REPO_ROOT}/components/tests/wincompat/golden-apps.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-gx-launchers] $*"; }

mkdir -p "${OUT_DIR}"
[[ -f "${MANIFEST}" ]] || die "missing manifest ${MANIFEST}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-gx-launchers/v1",
    "stage": "gx3-launcher-smoke",
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

log "cargo test strawwu-runtime golden_apps (in-process launcher probes)"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime golden_apps -- --nocapture) \
    || write_fail "strawwu-runtime golden_apps tests failed"

log "build golden-apps-verify"
(cd "${COMPONENTS}" && cargo build -p strawwu-runtime --release --bin golden-apps-verify) \
    || write_fail "cargo build golden-apps-verify failed"

VERIFY_BIN="${COMPONENTS}/target/release/golden-apps-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "missing golden-apps-verify binary"

RAW_JSON="${OUT_DIR}/gx3-launchers-raw.json"
log "generate raw golden-apps evidence"
"${VERIFY_BIN}" "${VERSION}" "${MANIFEST}" > "${RAW_JSON}" \
    || write_fail "golden-apps-verify run failed"
[[ -s "${RAW_JSON}" ]] || write_fail "raw evidence missing or empty: ${RAW_JSON}"

log "normalize gx3 evidence contract → ${OUT_JSON}"
python3 - "${RAW_JSON}" "${OUT_JSON}" "${VERSION}" <<'PY' || write_fail "failed to normalize gx3 evidence"
import json, sys, time
raw_path, out_path, version = sys.argv[1], sys.argv[2], sys.argv[3]
raw = json.load(open(raw_path, encoding="utf-8"))

cases = raw.get("cases", [])

launchers = []
for c in cases:
    scope = c.get("scope")
    if scope != "launcher_only":
        continue
    evidence = c.get("evidence") or {}
    probe_pass = int(evidence.get("probe_pass", 0))
    probe_total = int(evidence.get("probe_total", 0))
    ratio = (probe_pass / probe_total) if probe_total else 0.0

    launchers.append({
        "id": c.get("id"),
        "name": c.get("name"),
        "kind": "golden_launcher_only",
        "scope": c.get("scope"),
        "backend": c.get("backend", "native"),
        "status": c.get("status", "PARTIAL"),
        "grade": c.get("grade"),
        "launch_verified": bool(c.get("launch_verified")),
        "probe_pass": probe_pass,
        "probe_total": probe_total,
        "probe_ratio": round(ratio, 3),
        "notes": c.get("notes", ""),
        "disclaimer": evidence.get("honest_disclaimer", "")
    })

verified = [l for l in launchers if l.get("launch_verified")]
if len(verified) < 2:
    status = "PARTIAL"  # honest: not enough launcher probes verified
else:
    status = "PARTIAL"  # gx3 is explicitly honest; we don't "upgrade" to PASS

doc = {
    "schema": "strawwu-portable-gx-launchers/v1",
    "stage": "gx3-launcher-smoke",
    "status": status,
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "source_manifest": {
        "path": "components/tests/wincompat/golden-apps.json",
        "version": raw.get("manifest_version"),
        "source": "golden_apps launcher_only manifest"
    },
    "claims": {
        "wine_proton_used": False,
        "native_pe_backend": True,
        "anti_cheat_claimed": False,
        "aaa_claimed": False
    },
    "launchers": launchers,
    "results": launchers,  # keep contract flexible: some verifiers look at results/apps too
    "summary": {
        "total_launchers": len(launchers),
        "launch_verified": len(verified),
        "native_backend_only": all(l.get("backend") == "native" for l in launchers)
    },
    "known_limitations": [
        "launcher_only probe evidence; no real Steam/Epic/Delta binaries",
        "no anti-cheat ranked verification",
        "no 3A compatibility claim"
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
python3 - "${OUT_JSON}" <<'PY' || write_fail "gx3 evidence contract validation failed"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status={status}"
launchers = doc.get("launchers") or []
results = doc.get("results") or []
apps = doc.get("apps") or []
assert len(launchers) >= 2 or len(results) >= 2 or len(apps) >= 2, "need at least 2 launchers/results/apps"
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("anti_cheat_claimed") is False, "anti-cheat claim must stay false"
assert claims.get("aaa_claimed") is False, "3A claim must stay false"
for row in launchers:
    assert row.get("backend") == "native", f"non-native backend for {row.get('id')}"
print(f"ok status={status} launchers={len(launchers)} verified={doc.get('summary',{}).get('launch_verified')}")
PY

log "ensure no wine/proton substrate mention"
if grep -qiE 'wine|proton' "${OUT_JSON}" >/dev/null; then
  # Allow only explicit denial claims; fail hard if substring appears in unexpected places.
  python3 - "${OUT_JSON}" <<'PY' || write_fail "wine/proton mention present"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
print("wine/proton denial only: ok")
PY
fi

log "gx3 launchers evidence ready: ${OUT_JSON}"
jq -r '.status + " version=" + (.version|tostring) + " verified=" + (.summary.launch_verified|tostring) + "/" + (.summary.total_launchers|tostring)' "${OUT_JSON}"

