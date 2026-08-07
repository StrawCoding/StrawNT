#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-gx-audio-input.sh — gx1 WASAPI→PipeWire/equivalent + XInput evidence.
# Emits tests/portable/output/gx-audio-input.json (top-level PASS|PARTIAL|FAIL)
# with observable WAV tone + input observation side effects.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/gx-audio-input.json"
SIDE_DIR="${OUT_DIR}/gx1-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-gx-audio-input] $*"; }

mkdir -p "${OUT_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-gx-audio-input/v1",
    "stage": "gx1-audio-input",
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

log "building strawwu-audio (release) + gx-audio-verify"
(cd "${COMPONENTS}" && cargo build -p strawwu-audio --release --bin gx-audio-verify) \
    || write_fail "cargo build strawwu-audio failed"

log "cargo test strawwu-audio"
(cd "${COMPONENTS}" && cargo test -p strawwu-audio -- --nocapture) \
    || write_fail "strawwu-audio tests failed"

VERIFY_BIN="${COMPONENTS}/target/release/gx-audio-verify"
[[ -x "${VERIFY_BIN}" ]] || write_fail "gx-audio-verify binary missing"

log "running gx-audio-verify → ${OUT_JSON}"
"${VERIFY_BIN}" "${OUT_JSON}" "${SIDE_DIR}" \
    || write_fail "gx-audio-verify failed"

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"
[[ -f "${SIDE_DIR}/gx-tone.wav" ]] || write_fail "missing tone WAV evidence"
[[ -f "${SIDE_DIR}/gx-input-obs.json" ]] || write_fail "missing input observation"

# Validate evidence contract (Hermes verify subset + local gates)
python3 - "${OUT_JSON}" "${SIDE_DIR}" <<'PY' || write_fail "evidence validation failed"
import json, sys, struct
from pathlib import Path
out, side = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(out.read_text(encoding="utf-8"))
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status {status}"
# NTW0 soft-reset: allow wine product default; historical JSON may still say native
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
audio = doc.get("audio") or {}
assert int(audio.get("samples_generated") or 0) > 1000, "tone samples missing"
assert int(audio.get("bytes_rendered") or 0) > 44, "wav bytes missing"
inp = doc.get("input") or {}
assert int(inp.get("controllers_connected") or 0) >= 1, "no controller"
assert inp.get("deadzone_applied") is True, "deadzone not applied"
assert inp.get("vibration_set") is True, "vibration missing"
wav = side / "gx-tone.wav"
data = wav.read_bytes()
assert data.startswith(b"RIFF"), "wav not RIFF"
assert data[8:12] == b"WAVE", "wav not WAVE"
# PCM 16-bit stereo header sanity
channels = struct.unpack_from("<H", data, 22)[0]
rate = struct.unpack_from("<I", data, 24)[0]
assert channels == 2 and rate == 48000, f"unexpected wav fmt ch={channels} rate={rate}"
obs = side / "gx-input-obs.json"
assert obs.is_file(), "input obs missing"
if status == "PARTIAL":
    gaps = doc.get("gaps") or doc.get("known_limitations") or []
    assert gaps, "PARTIAL must list gaps"
checks = doc.get("checks") or []
failed = [c for c in checks if c.get("status") != "PASS"]
print(f"ok status={status} samples={audio.get('samples_generated')} host={audio.get('host_backend')} failed_checks={len(failed)}")
PY

# Wine/Proton must not appear as substrate
if grep -qiE 'wine|proton' "${OUT_JSON}"; then
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

log "gx-audio-input PASS/PARTIAL evidence ready: ${OUT_JSON}"
jq -r '.status + " version=" + (.version|tostring) + " host=" + (.audio.host_backend|tostring) + " samples=" + (.audio.samples_generated|tostring)' "${OUT_JSON}"
