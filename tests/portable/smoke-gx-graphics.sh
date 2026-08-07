#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-gx-graphics.sh — gx0 DXGI/D3D11→VK + wgl→GL/present evidence.
# Emits tests/portable/output/gx-graphics.json (top-level PASS|PARTIAL|FAIL)
# with observable triangle PPM + present observation side effects.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/gx-graphics.json"
SIDE_DIR="${OUT_DIR}/gx0-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-gx-graphics] $*"; }

mkdir -p "${OUT_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-gx-graphics/v1",
    "stage": "gx0-graphics-vk-gl",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked pass claim",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
    die "${msg}"
}

log "building strawwu-graphics (release) + gx-graphics-verify"
(cd "${COMPONENTS}" && cargo build -p strawwu-graphics --release --bin gx-graphics-verify) \
    || write_fail "cargo build strawwu-graphics failed"

log "cargo test strawwu-graphics pipeline/triangle"
(cd "${COMPONENTS}" && cargo test -p strawwu-graphics -- --nocapture) \
    || write_fail "strawwu-graphics tests failed"

VERIFY_BIN="${COMPONENTS}/target/release/gx-graphics-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "gx-graphics-verify binary missing"

log "running gx-graphics-verify → ${OUT_JSON}"
"${VERIFY_BIN}" "${OUT_JSON}" "${SIDE_DIR}" 640 480 \
    || write_fail "gx-graphics-verify failed"

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"
[[ -f "${SIDE_DIR}/gx-triangle.ppm" ]] || write_fail "missing triangle PPM evidence"
[[ -f "${SIDE_DIR}/gx-present.json" ]] || write_fail "missing present observation"

# Validate evidence contract (Hermes verify subset + local gates)
python3 - "${OUT_JSON}" "${SIDE_DIR}" <<'PY' || write_fail "evidence validation failed"
import json, sys
from pathlib import Path
out, side = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(out.read_text(encoding="utf-8"))
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status {status}"
# NTW0 soft-reset: allow wine product default; historical JSON may still say native
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
tri = doc.get("triangle") or {}
assert int(tri.get("drawn") or 0) >= 1, "no triangles drawn"
assert int(tri.get("pixels") or 0) > 100, "triangle pixels missing"
present = doc.get("present") or {}
assert int(present.get("vk_frames") or 0) >= 1, "vk present missing"
assert int(present.get("present_frames") or 0) >= 1, "present bridge missing"
ppm = side / "gx-triangle.ppm"
data = ppm.read_bytes()
assert data.startswith(b"P6"), "ppm not P6"
if status == "PARTIAL":
    gaps = doc.get("gaps") or doc.get("known_limitations") or []
    assert gaps, "PARTIAL must list gaps"
checks = doc.get("checks") or []
failed = [c for c in checks if c.get("status") != "PASS"]
print(f"ok status={status} triangles={tri.get('drawn')} pixels={tri.get('pixels')} failed_checks={len(failed)}")
PY

# Wine/Proton must not appear as substrate
if grep -qiE 'wine|proton' "${OUT_JSON}"; then
    # Allow only explicit denial claims
    if ! python3 - "${OUT_JSON}" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
# NTW0 soft-reset: allow wine product default; historical JSON may still say native
print("wine denial ok")
PY
    then
        write_fail "evidence mentions wine/proton incorrectly"
    fi
fi

log "gx-graphics PASS/PARTIAL evidence ready: ${OUT_JSON}"
jq -r '.status + " version=" + (.version|tostring) + " triangles=" + (.triangle.drawn|tostring) + " pixels=" + (.triangle.pixels|tostring)' "${OUT_JSON}"
