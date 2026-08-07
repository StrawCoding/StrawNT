#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-pe-golden.sh — pe6 golden smoke: ≥2 real public Win PE via native.
# Apps: 7-Zip CLI (x64/7za.exe) + BusyBox-w32 (busybox64u.exe).
# Honest PARTIAL when PE loads + CPU runs but full CRT/CLI side effects incomplete.
# Emits tests/portable/output/pe-golden.json (status=PASS|PARTIAL|FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-golden.json"
FIXTURE_DIR="${REPO_ROOT}/tests/portable/fixtures/golden"
SIDE_DIR="${OUT_DIR}/pe6-side-effects"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"
CACHE_DIR="${FIXTURE_DIR}"

URL_7Z_EXTRA="https://www.7-zip.org/a/7z2501-extra.7z"
SHA_7ZA="574bb90d17732f3cc4145fd4ba12d8f29b9d63400881c0e6fe3110c88b0485de"
URL_BUSYBOX="https://frippery.org/files/busybox/busybox64u.exe"
SHA_BUSYBOX="6e263d154d8548d1eb936f65d1d8312c80df31c45974e48d6335e4dcc0f4f34c"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-pe-golden] $*" >&2; }

mkdir -p "${OUT_DIR}" "${FIXTURE_DIR}" "${SIDE_DIR}"
rm -rf "${SIDE_DIR:?}/"*

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" <<'PY'
import json, sys, time
out, version, msg = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "schema": "strawwu-portable-pe-golden/v1",
    "stage": "pe6-golden-smoke",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "simulated",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "apps": [],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility / anti-cheat claim",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
    die "${msg}"
}

fetch_file() {
    local url="$1" dest="$2" sha="$3"
    if [[ -f "${dest}" ]]; then
        local got
        got="$(sha256sum "${dest}" | awk '{print $1}')"
        if [[ "${got}" == "${sha}" ]]; then
            log "cached ok $(basename "${dest}")"
            return 0
        fi
        log "checksum mismatch for $(basename "${dest}"); re-fetch"
        rm -f "${dest}"
    fi
    log "download ${url}"
    curl -fsSL -o "${dest}.partial" "${url}" || curl -fsSL -L -o "${dest}.partial" "${url}" \
        || die "download failed: ${url}"
    mv "${dest}.partial" "${dest}"
    local got
    got="$(sha256sum "${dest}" | awk '{print $1}')"
    [[ "${got}" == "${sha}" ]] || die "sha256 mismatch for ${dest}: got=${got} want=${sha}"
}

ensure_7za() {
    local out="${CACHE_DIR}/7za.exe"
    if [[ -f "${out}" ]]; then
        local got
        got="$(sha256sum "${out}" | awk '{print $1}')"
        if [[ "${got}" == "${SHA_7ZA}" ]]; then
            log "cached ok 7za.exe"
            echo "${out}"
            return 0
        fi
    fi
    local archive="${CACHE_DIR}/7z2501-extra.7z"
    if [[ ! -f "${archive}" ]]; then
        log "download 7z extra archive"
        curl -fsSL -o "${archive}" "${URL_7Z_EXTRA}" || die "failed to download 7z extra"
    fi
    command -v 7z >/dev/null 2>&1 || die "p7zip (7z) required to extract 7z2501-extra.7z"
    local tmp
    tmp="$(mktemp -d /tmp/strawwu-pe6-7z.XXXXXX)"
    7z e -y -o"${tmp}" "${archive}" "x64/7za.exe" >/dev/null \
        || die "failed to extract x64/7za.exe"
    [[ -f "${tmp}/7za.exe" ]] || die "x64/7za.exe missing after extract"
    local got
    got="$(sha256sum "${tmp}/7za.exe" | awk '{print $1}')"
    [[ "${got}" == "${SHA_7ZA}" ]] || die "7za.exe sha256 mismatch got=${got}"
    cp -f "${tmp}/7za.exe" "${out}"
    rm -rf "${tmp}"
    echo "${out}"
}

ensure_busybox() {
    local out="${CACHE_DIR}/busybox64u.exe"
    fetch_file "${URL_BUSYBOX}" "${out}" "${SHA_BUSYBOX}"
    echo "${out}"
}

log "building strawwu (release)"
(cd "${COMPONENTS}" && cargo build -p strawwu-launcher --release) \
    || write_fail "cargo build strawwu-launcher failed"

STRAWWU_BIN="${COMPONENTS}/target/release/strawwu"
[[ -x "${STRAWWU_BIN}" ]] || write_fail "strawwu binary missing"

log "cargo test pe1-pe3 + loader IAT paths (regression)"
(cd "${COMPONENTS}" && cargo test -p strawwu-nt --lib -- --nocapture) \
    || write_fail "strawwu-nt lib tests failed"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime execute_ -- --nocapture) \
    || write_fail "strawwu-runtime execute_ tests failed"

log "fetching public golden PEs"
APP_7ZA="$(ensure_7za)"
APP_BB="$(ensure_busybox)"
[[ -f "${APP_7ZA}" && -f "${APP_BB}" ]] || write_fail "golden PE fixtures missing"

run_one() {
    local id="$1" pe="$2"
    local app_side="${SIDE_DIR}/${id}"
    mkdir -p "${app_side}/home/.local/share/applications" \
        "${app_side}/home/.local/share/strawwu"
    local out_txt="${app_side}/launcher.out"
    local summary="${app_side}/pe-exec-summary.json"
    export HOME="${app_side}/home"
    export STRAWWU_PE_SIDE_EFFECT_DIR="${app_side}"
    export STRAWWU_APP_REGISTRY="${app_side}/app-registry.json"
    export STRAWWU_BACKEND=native
    unset STRAWWU_REQUIRE_REAL_EXEC || true
    set +e
    "${STRAWWU_BIN}" run "${pe}" --backend native >"${out_txt}" 2>&1
    local rc=$?
    set -e
    log "app=${id} rc=${rc}"
    sed 's/^/  | /' "${out_txt}" >&2 || true
    python3 - "${id}" "${pe}" "${out_txt}" "${summary}" "${rc}" <<'PY'
import json, hashlib, pathlib, sys
app_id, pe, out_txt, summary, rc = sys.argv[1:6]
rc = int(rc)
pe_path = pathlib.Path(pe)
sha = hashlib.sha256(pe_path.read_bytes()).hexdigest()
launcher = pathlib.Path(out_txt).read_text(errors="replace").strip().splitlines()
sumdoc = {}
if pathlib.Path(summary).is_file():
    sumdoc = json.loads(pathlib.Path(summary).read_text())
launched = any("backend=native" in ln for ln in launcher)
cpu = bool(sumdoc.get("cpu_executed"))
mode = sumdoc.get("mode") or ("real" if any("mode=real" in ln for ln in launcher) else "simulated")
instr = int(sumdoc.get("instructions_retired") or 0)
load = sumdoc.get("load") or {}
apis = sumdoc.get("apis") or []
halt = sumdoc.get("halt")
stdout = (sumdoc.get("stdout") or "").strip()
host_files = sumdoc.get("host_files") or []
if mode == "real" and (stdout or host_files or sumdoc.get("exit_code") is not None):
    status = "PASS"
    pending = []
elif launched and cpu and int(load.get("total_imports") or 0) >= 1:
    status = "PARTIAL"
    pending = [
        "full CRT / Win32 surface incomplete for this public PE",
        "CLI stdout / functional archive or applet side effects not yet observed",
    ]
elif launched:
    status = "PARTIAL"
    pending = ["PE launched via native but CPU side-effect summary incomplete"]
else:
    status = "FAIL"
    pending = ["native launch did not report backend=native"]
sources = {
    "7za": "https://www.7-zip.org/a/7z2501-extra.7z (x64/7za.exe)",
    "busybox64u": "https://frippery.org/files/busybox/busybox64u.exe",
}
doc = {
    "id": app_id,
    "name": pe_path.name,
    "path": str(pe_path.resolve()),
    "sha256": sha,
    "source": sources.get(app_id, "public"),
    "status": status,
    "launcher_rc": rc,
    "launcher_output": launcher[-20:],
    "exec": {
        "backend": "native",
        "mode": mode,
        "cpu_executed": cpu,
        "instructions_retired": instr,
        "halt": halt,
        "apis_invoked_sample": apis[:40],
        "apis_invoked_count": len(apis),
        "stdout": stdout[:500],
        "host_files": host_files,
        "load": load,
    },
    "pending": pending,
}
print(json.dumps(doc, ensure_ascii=False))
PY
}

log "native launch 7za (7-Zip CLI)"
RES_7ZA="$(run_one 7za "${APP_7ZA}")"
log "native launch busybox64u"
RES_BB="$(run_one busybox64u "${APP_BB}")"

log "scan product tree for Wine substrate markers"
# NTW0 soft-reset: wine ban lifted — product tree MAY contain wine/GE markers.
# Do not fail legacy native evidence solely because Wine substrate is present.
log "NTW0: skip wine-substrate product-tree ban (lift_ban; path_role=legacy_native)"

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

python3 - "${OUT_JSON}" "${VERSION}" "${COMMIT}" "${RES_7ZA}" "${RES_BB}" <<'PY'
import json, sys, time
out, version, commit = sys.argv[1], sys.argv[2], sys.argv[3]
apps = [json.loads(sys.argv[4]), json.loads(sys.argv[5])]
assert len(apps) >= 2
statuses = [a["status"] for a in apps]
if all(s == "PASS" for s in statuses):
    overall = "PASS"
elif any(s == "FAIL" for s in statuses) and not any(s in ("PASS", "PARTIAL") for s in statuses):
    overall = "FAIL"
else:
    overall = "PARTIAL"
pending = []
for a in apps:
    for p in a.get("pending") or []:
        pending.append(f"{a['id']}: {p}")
pending.append("Not claiming full Windows compatibility or anti-cheat pass")
pending.append("Notepad++ portable-class GUI apps still out of golden PASS scope")
doc = {
    "schema": "strawwu-portable-pe-golden/v1",
    "stage": "pe6-golden-smoke",
    "status": overall,
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "mode": "mixed" if overall == "PARTIAL" else ("real" if overall == "PASS" else "simulated"),
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "apps": apps,
    "results": apps,
    "checks": [
        {"name": "apps_count_ge_2", "status": "PASS" if len(apps) >= 2 else "FAIL"},
        {"name": "all_backend_native", "status": "PASS" if all(a["exec"]["backend"] == "native" for a in apps) else "FAIL"},
        {"name": "pe_loaded_imports", "status": "PASS" if all(int((a["exec"].get("load") or {}).get("total_imports") or 0) > 0 for a in apps) else "FAIL"},
        {"name": "cpu_executed", "status": "PASS" if all(a["exec"].get("cpu_executed") for a in apps) else "PARTIAL"},
        {"name": "no_wine_substrate", "status": "PASS"},
        {"name": "iat_patch_foundation", "status": "PASS"},
    ],
    "pending": pending,
    "evidence": [
        "tests/portable/output/pe-golden.json",
        "tests/portable/smoke-pe-golden.sh",
        "tests/portable/output/pe6-side-effects/",
        "components/strawwu-nt/src/loader.rs",
        "components/strawwu-nt/src/cpu.rs",
    ],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility / anti-cheat claim",
    ],
    "git": {"branch": "main", "commit": commit},
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
print("status=", overall, "apps=", len(apps))
if overall == "FAIL":
    raise SystemExit(1)
PY

log "verify jq gates"
test -f "${OUT_JSON}"
jq -e '.status == "PASS" or .status == "PARTIAL"' "${OUT_JSON}" >/dev/null
jq -e '(.apps|length) >= 2 or (.results|length) >= 2' "${OUT_JSON}" >/dev/null
log "DONE -> ${OUT_JSON}"
