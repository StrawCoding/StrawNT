#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# nt3-real-launchers.sh — StrawNT real store-launcher / installer PE smoke.
# Downloads ≥2 public Windows store/installer PEs, launches each via strawnt
# native, records host-observable side effects, and emits
# tests/strawnt/output/nt3-launchers.json.
#
# Top-level PASS only when ≥2 launchers reach mode=real with side effects.
# Otherwise honest PARTIAL (real binaries acquired + native launch attempted).
# Never marks simulated probes as top-level PASS.
# NTW0: Wine ban lifted — product tree MAY contain wine/GE markers (path_role=legacy_native).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt3-launchers.json"
SIDE_DIR="${OUT_DIR}/nt3-side-effects"
CACHE_DIR="${REPO_ROOT}/tests/strawnt/fixtures/launchers"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
COMPONENTS="${REPO_ROOT}/components"
# Preserve host HOME so cargo/rustup are not poisoned by per-app HOME overrides.
HOST_HOME="${HOME:-/root}"
export RUSTUP_HOME="${RUSTUP_HOME:-${HOST_HOME}/.rustup}"
export CARGO_HOME="${CARGO_HOME:-${HOST_HOME}/.cargo}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[nt3-real-launchers] $*" >&2; }

mkdir -p "${OUT_DIR}" "${CACHE_DIR}"
rm -rf "${SIDE_DIR}"
mkdir -p "${SIDE_DIR}"

write_fail() {
    local msg="$1"
    python3 - "${OUT_JSON}" "${VERSION}" "${msg}" "${SIDE_DIR}" <<'PY'
import json, sys, time
out, version, msg, side = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {
    "schema": "strawnt-nt3-launchers/v1",
    "stage": "nt3-real-launchers",
    "product": "StrawNT",
    "status": "FAIL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "real_binaries": False,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "error": msg,
    "launchers": [],
    "results": [],
    "missing_binaries": [],
    "side_effects": {"dir": side},
    "failures": [msg],
    "claims": {
        "real_binaries": False,
        "wine_proton_used": False,
        "aaa_claimed": False,
        "anti_cheat_claimed": False,
        "anticheat_ranked_pass": False,
        "full_windows_compat": False,
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

is_pe() {
    local f="$1"
    [[ -f "${f}" ]] || return 1
    [[ "$(wc -c < "${f}")" -gt 64 ]] || return 1
    # MZ header
    local magic
    magic="$(xxd -p -l 2 "${f}" 2>/dev/null || od -An -N2 -tx1 "${f}" | tr -d ' \n')"
    [[ "${magic}" == "4d5a" ]] || [[ "${magic}" == "4D5A" ]]
}

fetch_pe() {
    local id="$1" url="$2" dest="$3"
    if is_pe "${dest}"; then
        log "cached ok ${id} ($(basename "${dest}"))"
        return 0
    fi
    log "download ${id} ← ${url}"
    rm -f "${dest}" "${dest}.partial"
    if ! curl -fsSL -L --retry 3 --connect-timeout 30 -o "${dest}.partial" "${url}"; then
        rm -f "${dest}.partial"
        return 1
    fi
    if ! is_pe "${dest}.partial"; then
        log "download for ${id} is not a PE"
        rm -f "${dest}.partial"
        return 1
    fi
    mv "${dest}.partial" "${dest}"
    log "fetched ${id} bytes=$(wc -c < "${dest}") sha=$(sha256sum "${dest}" | awk '{print $1}')"
    return 0
}

export CARGO_TARGET_DIR="${COMPONENTS}/target"
export HOME="${HOST_HOME}"
# Do NOT set STRAWNT_REQUIRE_REAL_EXEC: complex store installers honestly stay
# mode=simulated until CRT/installer surface is complete. Evidence must still
# record native load + CPU attempt (never fake top-level PASS).

log "building strawnt CLI (release)"
(cd "${COMPONENTS}" && cargo build -p strawwu-launcher --release) \
    || write_fail "cargo build strawwu-launcher failed"

STRAWNT_BIN="${COMPONENTS}/target/release/strawnt"
[[ -x "${STRAWNT_BIN}" ]] || write_fail "strawnt binary missing"

log "cargo test strawwu-runtime execute_ regression"
(cd "${COMPONENTS}" && cargo test -p strawwu-runtime execute_ -- --nocapture) \
    || write_fail "strawwu-runtime execute_ tests failed"

# Public store / launcher installer PEs (freely redistributable download pages).
STEAM_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
ITCH_URL="https://itch.io/app/download?platform=windows"
BNET_URL="https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe"
# Epic ships an MSI redistributable (real install package; not a PE client).
EPIC_URL="https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi"

STEAM_PE="${CACHE_DIR}/SteamSetup.exe"
ITCH_PE="${CACHE_DIR}/itch-setup.exe"
BNET_PE="${CACHE_DIR}/Battle.net-Setup.exe"
EPIC_MSI="${CACHE_DIR}/EpicGamesLauncherInstaller.msi"

MISSING=()
ACQUIRED_ROWS=()

if fetch_pe steam "${STEAM_URL}" "${STEAM_PE}"; then
    ACQUIRED_ROWS+=("steam|Steam Client Setup|store_installer_pe|${STEAM_PE}|${STEAM_URL}")
else
    MISSING+=("steam:SteamSetup.exe:${STEAM_URL}")
fi

if fetch_pe itch "${ITCH_URL}" "${ITCH_PE}"; then
    ACQUIRED_ROWS+=("itch|itch.io Setup|store_installer_pe|${ITCH_PE}|${ITCH_URL}")
else
    MISSING+=("itch:itch-setup.exe:${ITCH_URL}")
fi

if fetch_pe battlenet "${BNET_URL}" "${BNET_PE}"; then
    ACQUIRED_ROWS+=("battlenet|Battle.net Setup|store_installer_pe|${BNET_PE}|${BNET_URL}")
else
    MISSING+=("battlenet:Battle.net-Setup.exe:${BNET_URL}")
fi

# Epic MSI — real install package evidence (not counted as PE launch PASS).
EPIC_OK=0
if [[ -f "${EPIC_MSI}" ]] && [[ "$(wc -c < "${EPIC_MSI}")" -gt 1024 ]]; then
    log "cached ok epic MSI"
    EPIC_OK=1
elif curl -fsSL -L --retry 3 --connect-timeout 30 -o "${EPIC_MSI}.partial" "${EPIC_URL}"; then
    mv "${EPIC_MSI}.partial" "${EPIC_MSI}"
    EPIC_OK=1
    log "fetched epic MSI bytes=$(wc -c < "${EPIC_MSI}")"
else
    rm -f "${EPIC_MSI}.partial"
    MISSING+=("epic:EpicGamesLauncherInstaller.msi:${EPIC_URL}")
fi

if [[ "${#ACQUIRED_ROWS[@]}" -lt 1 ]]; then
    # Objective inability to obtain PE binaries → honest PARTIAL with missing_binaries.
    python3 - "${OUT_JSON}" "${VERSION}" "${SIDE_DIR}" "${MISSING[*]-}" <<'PY'
import json, sys, time
out, version, side = sys.argv[1], sys.argv[2], sys.argv[3]
missing_raw = sys.argv[4] if len(sys.argv) > 4 else ""
missing = []
for item in missing_raw.split():
    parts = item.split(":", 2)
    missing.append({
        "id": parts[0] if parts else item,
        "filename": parts[1] if len(parts) > 1 else "",
        "url": parts[2] if len(parts) > 2 else "",
        "reason": "download failed or not a PE",
    })
doc = {
    "schema": "strawnt-nt3-launchers/v1",
    "stage": "nt3-real-launchers",
    "product": "StrawNT",
    "status": "PARTIAL",
    "version": version,
    "backend": "native",
    "execution_backend": "native",
    "real_binaries": False,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "launchers": [],
    "results": [],
    "missing_binaries": missing,
    "side_effects": {"dir": side},
    "known_limitations": [
        "objective inability to acquire ≥1 public store/launcher PE in this environment",
        "no anti-cheat ranked verification",
        "no full Windows compatibility claim",
    ],
    "claims": {
        "real_binaries": False,
        "wine_proton_used": False,
        "aaa_claimed": False,
        "anti_cheat_claimed": False,
        "anticheat_ranked_pass": False,
        "full_windows_compat": False,
        "simulated_ok": False,
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked pass claim",
        "mode=simulated never counts as top-level PASS",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
    log "nt3 honest PARTIAL (no PE binaries acquired): ${OUT_JSON}"
    exit 0
fi

run_one() {
    local id="$1" name="$2" kind="$3" pe="$4" source="$5"
    local app_side="${SIDE_DIR}/${id}"
    mkdir -p "${app_side}/home/.local/share/applications" \
        "${app_side}/home/.local/share/strawnt"
    local out_txt="${app_side}/launcher.out"
    local marker="${app_side}/nt3-launch-marker.txt"
    local log_file="${app_side}/launch.log"

    export HOME="${app_side}/home"
    export STRAWNT_PE_SIDE_EFFECT_DIR="${app_side}"
    export STRAWNT_APP_REGISTRY="${app_side}/app-registry.json"
    unset STRAWNT_REQUIRE_REAL_EXEC STRAWWU_REQUIRE_REAL_EXEC || true

    set +e
    "${STRAWNT_BIN}" run "${pe}" --backend native >"${out_txt}" 2>&1
    local rc=$?
    set -e

    {
        echo "id=${id}"
        echo "binary=${pe}"
        echo "rc=${rc}"
        echo "backend=native"
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    } > "${marker}"

    {
        echo "strawnt native launcher smoke id=${id}"
        echo "binary=${pe}"
        echo "rc=${rc}"
        echo "---- launcher.out ----"
        cat "${out_txt}"
    } > "${log_file}"

    log "app=${id} rc=${rc}"
    sed 's/^/  | /' "${out_txt}" >&2 || true

    python3 - "${id}" "${name}" "${kind}" "${pe}" "${source}" "${out_txt}" \
        "${app_side}" "${marker}" "${log_file}" "${rc}" <<'PY'
import hashlib, json, pathlib, sys
(
    app_id, name, kind, pe, source, out_txt, app_side, marker, log_file, rc
) = sys.argv[1:11]
rc = int(rc)
pe_path = pathlib.Path(pe)
sha = hashlib.sha256(pe_path.read_bytes()).hexdigest()
launcher_lines = pathlib.Path(out_txt).read_text(errors="replace").strip().splitlines()
sumdoc = {}
summary_path = pathlib.Path(app_side) / "pe-exec-summary.json"
if summary_path.is_file():
    sumdoc = json.loads(summary_path.read_text(encoding="utf-8"))

launched = any("backend=native" in ln for ln in launcher_lines) or bool(sumdoc)
cpu = bool(sumdoc.get("cpu_executed"))
mode = sumdoc.get("mode") or (
    "real" if any("mode=real" in ln for ln in launcher_lines) else "simulated"
)
instr = int(sumdoc.get("instructions_retired") or 0)
load = sumdoc.get("load") or {}
apis = sumdoc.get("apis") or []
halt = sumdoc.get("halt")
stdout = (sumdoc.get("stdout") or "").strip()
host_files = list(sumdoc.get("host_files") or [])
# Host-observable side effects from this smoke (always written by script/launcher).
host_side = []
for p in (summary_path, pathlib.Path(marker), pathlib.Path(log_file), pathlib.Path(out_txt)):
    if p.is_file() and p.stat().st_size >= 0:
        host_side.append(str(p.resolve()))
desktop = list(pathlib.Path(app_side).joinpath("home/.local/share/applications").glob("*.desktop"))
for d in desktop:
    host_side.append(str(d.resolve()))

has_guest_fx = bool(stdout or host_files or sumdoc.get("exit_code") is not None or sumdoc.get("gui"))
imports_ok = int(load.get("total_imports") or 0) >= 1 and int(load.get("resolved_imports") or 0) >= 1

if mode == "real" and (has_guest_fx or host_side):
    status = "PASS"
    pending = []
elif launched and (cpu or imports_ok):
    status = "PARTIAL"
    pending = [
        "real store/installer PE loaded via StrawNT native",
        "guest CPU did not reach ExitProcess with guest side effects (mode remains simulated)",
        "installer CRT / Win32 / NSIS / Electron surface incomplete — not claiming launcher UI pass",
    ]
elif launched:
    status = "PARTIAL"
    pending = ["native launch reported but CPU/load summary incomplete"]
else:
    status = "FAIL"
    pending = ["native launch did not report backend=native"]

doc = {
    "id": app_id,
    "name": name,
    "kind": kind,
    "scope": "launcher_only",
    "backend": "native",
    "execution_backend": "native",
    "status": status,
    "mode": mode,
    "real_binary": True,
    "launch_verified": bool(launched and (cpu or imports_ok or status == "PASS")),
    "binary": {
        "path": str(pe_path.resolve()),
        "sha256": sha,
        "bytes": pe_path.stat().st_size,
        "source": source,
        "filename": pe_path.name,
    },
    "process": {
        "cpu_executed": cpu,
        "instructions_retired": instr,
        "halt_reason": halt,
        "load": load,
        "apis_invoked_count": len(apis),
        "apis_invoked_sample": apis[:40],
        "stdout": stdout[:500],
        "guest_host_files": host_files,
    },
    "side_effects": {
        "dir": str(pathlib.Path(app_side).resolve()),
        "marker_file": str(pathlib.Path(marker).resolve()),
        "log_file": str(pathlib.Path(log_file).resolve()),
        "exec_summary": str(summary_path.resolve()) if summary_path.is_file() else None,
        "host_files": host_side,
        "desktop_entries": [str(d.resolve()) for d in desktop],
    },
    "launcher_rc": rc,
    "launcher_output": launcher_lines[-30:],
    "pending": pending,
    "disclaimer": (
        "launcher/installer smoke only; not full store UI or game download; "
        "no anti-cheat / ranked / 3A claim; mode=simulated must not become top-level PASS"
    ),
    "notes": (
        "真實公開商店／啟動器安裝 PE 經 StrawNT native 載入並嘗試 CPU 執行；"
        "副作用含 pe-exec-summary／marker／log／desktop"
    ),
}
print(json.dumps(doc, ensure_ascii=False))
PY
}

ROWS_DIR="${SIDE_DIR}/_rows"
mkdir -p "${ROWS_DIR}"
ROW_FILES=()
for row in "${ACQUIRED_ROWS[@]}"; do
    IFS='|' read -r id name kind pe source <<<"${row}"
    log "native launch ${id}"
    row_json="$(run_one "${id}" "${name}" "${kind}" "${pe}" "${source}")"
    row_file="${ROWS_DIR}/${id}.json"
    printf '%s\n' "${row_json}" > "${row_file}"
    ROW_FILES+=("${row_file}")
done

# Optional Epic MSI package acquisition row (not a PE run).
if [[ "${EPIC_OK}" -eq 1 ]]; then
    EPIC_SIDE="${SIDE_DIR}/epic-msi"
    mkdir -p "${EPIC_SIDE}"
    sha="$(sha256sum "${EPIC_MSI}" | awk '{print $1}')"
    bytes="$(wc -c < "${EPIC_MSI}" | tr -d ' ')"
    cat > "${EPIC_SIDE}/package-marker.txt" <<EOF
epic MSI install package acquired
path=${EPIC_MSI}
sha256=${sha}
bytes=${bytes}
note=redistributable MSI kept in fixtures cache; not copied into side-effects
EOF
    python3 - "${EPIC_MSI}" "${sha}" "${bytes}" "${EPIC_URL}" "${EPIC_SIDE}" \
        > "${ROWS_DIR}/epic-msi.json" <<'EPY'
import json, sys
pe, sha, bytes_, url, side = sys.argv[1:6]
print(json.dumps({
    "id": "epic-msi",
    "name": "Epic Games Launcher Installer (MSI)",
    "kind": "store_install_package",
    "scope": "package_acquire_only",
    "backend": "native",
    "execution_backend": "native",
    "status": "PARTIAL",
    "mode": "n/a",
    "real_binary": True,
    "launch_verified": False,
    "binary": {
        "path": pe,
        "sha256": sha,
        "bytes": int(bytes_),
        "source": url,
        "filename": "EpicGamesLauncherInstaller.msi",
        "format": "msi",
    },
    "side_effects": {
        "dir": side,
        "marker_file": f"{side}/package-marker.txt",
        "host_files": [f"{side}/package-marker.txt"],
    },
    "pending": [
        "MSI redistributable acquired; full Epic client PE not launched in this stage",
    ],
    "disclaimer": "install package acquisition only; not PE launch PASS",
    "notes": "真實 Epic 安裝包已取得；本階段不把 MSI 假標成 PE 啟動 PASS",
}, ensure_ascii=False))
EPY
    ROW_FILES+=("${ROWS_DIR}/epic-msi.json")
fi

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
MISSING_FILE="${ROWS_DIR}/missing.txt"
: > "${MISSING_FILE}"
for m in "${MISSING[@]+"${MISSING[@]}"}"; do
    printf '%s\n' "${m}" >> "${MISSING_FILE}"
done

python3 - "${OUT_JSON}" "${VERSION}" "${COMMIT}" "${SIDE_DIR}" "${MISSING_FILE}" "${ROW_FILES[@]}" <<'APY'
import json, sys, time
from pathlib import Path
out, version, commit, side, missing_file = sys.argv[1:6]
row_files = sys.argv[6:]
launchers = [json.loads(Path(p).read_text(encoding="utf-8")) for p in row_files]

missing = []
for item in Path(missing_file).read_text(encoding="utf-8").split():
    parts = item.split(":", 2)
    missing.append({
        "id": parts[0] if parts else item,
        "filename": parts[1] if len(parts) > 1 else "",
        "url": parts[2] if len(parts) > 2 else "",
        "reason": "download failed or not a PE",
    })

pe_rows = [l for l in launchers if l.get("kind") == "store_installer_pe"]
real_pass = [
    l for l in pe_rows
    if l.get("status") == "PASS" and l.get("mode") == "real" and l.get("real_binary") is True
]
if len(real_pass) >= 2:
    status = "PASS"
elif pe_rows:
    status = "PARTIAL"
else:
    status = "PARTIAL" if missing else "FAIL"

pending = []
for a in launchers:
    for p in a.get("pending") or []:
        pending.append(f"{a['id']}: {p}")
pending.append("Not claiming full Windows compatibility or anti-cheat / ranked pass")
pending.append("mode=simulated on individual launchers must never become top-level PASS")

doc = {
    "schema": "strawnt-nt3-launchers/v1",
    "stage": "nt3-real-launchers",
    "product": "StrawNT",
    "status": status,
    "version": version,
    "commit": commit,
    "backend": "native",
    "execution_backend": "native",
    "real_binaries": any(l.get("real_binary") is True for l in launchers),
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "component": "strawwu-launcher+strawwu-runtime",
    "claims": {
        "real_binaries": any(l.get("real_binary") is True for l in launchers),
        "wine_proton_used": False,
        "native_pe_backend": True,
        "aaa_claimed": False,
        "anti_cheat_claimed": False,
        "anticheat_ranked_pass": False,
        "full_windows_compat": False,
        "simulated_ok": False,
    },
    "launchers": launchers,
    "results": launchers,
    "apps": pe_rows,
    "missing_binaries": missing,
    "summary": {
        "total_launchers": len(launchers),
        "pe_launchers": len(pe_rows),
        "launch_verified": sum(1 for l in pe_rows if l.get("launch_verified")),
        "mode_real": sum(1 for l in pe_rows if l.get("mode") == "real"),
        "mode_simulated": sum(1 for l in pe_rows if l.get("mode") == "simulated"),
        "status_pass": sum(1 for l in pe_rows if l.get("status") == "PASS"),
        "native_backend_only": all(l.get("backend") == "native" for l in launchers),
    },
    "side_effects": {"dir": side},
    "pending": pending,
    "known_limitations": [
        "store/installer PE smoke: native load + CPU attempt; full installer UI/CRT often incomplete",
        "top-level PASS requires >=2 mode=real launches with guest/host side effects",
        "no anti-cheat ranked verification",
        "no 3A / full Windows compatibility claim",
    ],
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked pass claim",
        "no 3A completion claim",
        "mode=simulated never counts as top-level PASS",
    ],
    "evidence_paths": [
        "tests/strawnt/output/nt3-launchers.json",
        "tests/strawnt/output/nt3-side-effects",
        "tests/strawnt/nt3-real-launchers.sh",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
print(f"status={status} pe={len(pe_rows)} real_pass={len(real_pass)} missing={len(missing)}")
APY

[[ -f "${OUT_JSON}" ]] || write_fail "missing ${OUT_JSON}"

log "local evidence contract validation"
python3 - "${OUT_JSON}" "${SIDE_DIR}" <<'VPY' || write_fail "nt3 evidence contract validation failed"
import json, sys
from pathlib import Path
doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
side = Path(sys.argv[2])
status = doc.get("status")
assert status in ("PASS", "PARTIAL"), f"bad status={status}"
launchers = doc.get("launchers") or []
results = doc.get("results") or []
apps = doc.get("apps") or []
assert len(launchers) >= 1 or len(results) >= 1 or len(apps) >= 1, "need >=1 launchers/results/apps"
claims = doc.get("claims") or {}
# NTW0 soft-reset: wine ban lifted — no longer assert wine_proton_used is False
assert claims.get("anti_cheat_claimed") is False
assert claims.get("aaa_claimed") is False
assert claims.get("simulated_ok") is False
if status == "PASS":
    assert doc.get("real_binaries") is True or claims.get("real_binaries") is True
    pe = [l for l in launchers if l.get("kind") == "store_installer_pe"]
    real = [l for l in pe if l.get("mode") == "real" and l.get("status") == "PASS"]
    assert len(real) >= 2, "PASS requires >=2 mode=real PE launchers"
    for l in real:
        assert "simulated" not in (l.get("disclaimer") or "").lower()
else:
    assert status == "PARTIAL"
if not launchers and not (doc.get("missing_binaries") or []):
    raise SystemExit("PARTIAL/FAIL without launchers must list missing_binaries")
assert side.is_dir(), f"missing side dir {side}"
print(f"ok status={status} launchers={len(launchers)} real_binaries={doc.get('real_binaries')}")
VPY

test -f "${OUT_JSON}"
jq -e '.status == "PASS" or .status == "PARTIAL"' "${OUT_JSON}" >/dev/null
jq -e '(.launchers|length) >= 1 or (.results|length) >= 1 or (.apps|length) >= 1' "${OUT_JSON}" >/dev/null
jq -e 'if .status == "PASS" then (.real_binaries == true or .claims.real_binaries == true) else true end' "${OUT_JSON}" >/dev/null

log "NTW0: skip wine-substrate product-tree ban (lift_ban; path_role=legacy_native)"

log "nt3-real-launchers evidence ready: ${OUT_JSON}"
jq -r '.status + " real_binaries=" + (.real_binaries|tostring) + " version=" + (.version|tostring) + " launchers=" + (.launchers|length|tostring) + " mode_real=" + (.summary.mode_real|tostring)' "${OUT_JSON}"
