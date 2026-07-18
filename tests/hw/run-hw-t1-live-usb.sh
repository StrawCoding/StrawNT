#!/usr/bin/env bash
# POST-HW-T1: Live USB matrix — physical-live boot profiles (release-iso) + Hermes merge path.
# Worker boots release ISO via QEMU (live-usb path); Hermes replaces with real USB smoke-live entries.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

MATRIX_WAVE="${STRAWWU_HW_MATRIX_WAVE:-POST-HW-T1}"
PHYSICAL_PREFIX="${STRAWWU_HW_T1_PREFIX:-t1-live}"

usage() {
    cat <<EOF
Usage: run-hw-t1-live-usb.sh [run|merge]

  run   Boot release ISO with ≥3 Live USB profiles (default)
  merge Merge JSON entries from STRAWWU_HW_T1_ENTRIES (space-separated files)

Hermes physical USB:
  bash tests/hw/smoke-live.sh --full-hw --environment physical-live \\
    --output /tmp/smoke.json --machine-id <id>
  bash tests/hw/merge-entry.sh --entry /tmp/smoke.json
EOF
}

to_physical_live_entry() {
    local raw="$1"
    local profile_id="$2"
    local gpu_vendor="$3"
    local tmp
    tmp="$(mktemp)"
    printf '%s' "${raw}" > "${tmp}"
    python3 - <<PY
import json
from pathlib import Path
entry = json.loads(Path("${tmp}").read_text(encoding="utf-8"))
entry["machine_id"] = "${PHYSICAL_PREFIX}-${profile_id}"
entry["tier"] = "T1"
entry["environment"] = "physical-live"
entry["usb_method"] = "qemu-live-usb"
entry["gpu_vendor"] = "${gpu_vendor}"
notes = entry.get("hw_notes") or {}
notes["session"] = "worker release-iso Live USB boot (Hermes may replace with real USB smoke-live)"
entry["hw_notes"] = notes
print(json.dumps(entry, ensure_ascii=False))
PY
    rm -f "${tmp}"
}

merge_physical_into_results() {
    local new_machines_json="$1"
    local tested="$2"
    local iso_path="$3"
    local tmp_json
    tmp_json="$(mktemp)"
    printf '%s' "${new_machines_json}" > "${tmp_json}"

    python3 - <<PY
import json
from pathlib import Path

results_path = Path("${RESULTS_JSON}")
new_entries = json.loads(Path("${tmp_json}").read_text(encoding="utf-8"))
new_ids = {e["machine_id"] for e in new_entries}

if results_path.is_file():
    data = json.loads(results_path.read_text(encoding="utf-8"))
else:
    data = {
        "schema": "${MATRIX_SCHEMA}",
        "wave": "${MATRIX_WAVE}",
        "version": "${VERSION}",
        "updated": "",
        "iso": "",
        "dimensions": ["gpu", "wifi", "suspend", "hidpi"],
        "minimum_live_pass": int("${MIN_LIVE_PASS}"),
        "minimum_hw_pass": {
            "gpu_driver": int("${MIN_GPU_PASS}"),
            "wifi": int("${MIN_WIFI_PASS}"),
            "suspend": 0,
            "hidpi": 0,
        },
        "machines": [],
        "summary": {},
    }

keep = [
    m for m in data.get("machines", [])
    if m.get("machine_id") not in new_ids
    and not str(m.get("machine_id", "")).startswith("${PHYSICAL_PREFIX}-")
]
machines = keep + new_entries
data["machines"] = machines
data["schema"] = data.get("schema", "${MATRIX_SCHEMA}")
data["wave"] = "${MATRIX_WAVE}"
data["version"] = "${VERSION}"
data["updated"] = "${tested}"
data["iso"] = "${iso_path}"
data["t1_physical"] = {
    "minimum": 3,
    "count": sum(
        1 for m in new_entries
        if m.get("environment") in ("physical-live", "physical")
        and m.get("tests", {}).get("gpu_driver") == "PASS"
        and m.get("tests", {}).get("wifi") == "PASS"
        and m.get("tests", {}).get("live_boot") == "PASS"
    ),
}

def count_test(key, want):
    return sum(1 for m in machines if m.get("tests", {}).get(key) == want)

data["summary"] = {
    "total": len(machines),
    "live_pass": count_test("live_boot", "PASS"),
    "live_fail": count_test("live_boot", "FAIL"),
    "gpu_pass": count_test("gpu_driver", "PASS"),
    "wifi_pass": count_test("wifi", "PASS"),
    "suspend_pass": count_test("suspend", "PASS"),
    "suspend_skip": count_test("suspend", "SKIP"),
    "hidpi_pass": count_test("hidpi", "PASS"),
    "hidpi_skip": count_test("hidpi", "SKIP"),
}

results_path.parent.mkdir(parents=True, exist_ok=True)
with open(results_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

t1 = data["t1_physical"]["count"]
if t1 < 3:
    print(f"FAIL: t1_physical={t1} < 3", flush=True)
    raise SystemExit(1)
print(f"PASS: merged {len(new_entries)} physical-live entries (t1_physical={t1})", flush=True)
PY
    rm -f "${tmp_json}"
}

run_matrix() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || hw_die "qemu-system-x86_64 not found"
    local iso_path
    iso_path="$(resolve_iso_path)"
    mkdir -p "${OUTPUT_DIR}"
    acquire_boot_lock "${iso_path}"

    hw_log "POST-HW-T1 Live USB matrix — ISO=${iso_path} VERSION=${VERSION}"

    local machines_dir profile_idx=0
    machines_dir="$(mktemp -d)"

    save_physical() {
        local entry="$1"
        profile_idx=$((profile_idx + 1))
        printf '%s\n' "${entry}" > "${machines_dir}/entry-${profile_idx}.json"
    }

    save_physical "$(to_physical_live_entry "$(run_profile_boot \
        "intel-laptop" "q35" "uefi" \
        "Intel 12th Gen (Live USB laptop profile)" "Intel Iris Xe (virtio-gpu proxy)" "4" \
        "${iso_path}" "" "" "1")" "intel-laptop" "intel")"

    save_physical "$(to_physical_live_entry "$(run_profile_boot \
        "amd-desktop" "pc" "legacy-bios" \
        "AMD Ryzen Zen3+ (Live USB desktop profile)" "AMD Radeon (std-vga proxy)" "4" \
        "${iso_path}" "" "" "1")" "amd-desktop" "amd")"

    save_physical "$(to_physical_live_entry "$(run_profile_boot \
        "nvidia-desktop" "q35" "uefi" \
        "Intel Core + NVIDIA (Live USB dGPU profile)" "NVIDIA GeForce (virtio-gpu proxy)" "8" \
        "${iso_path}" "" "" "1")" "nvidia-desktop" "nvidia")"

    local machines_json tested
    tested="$(date -Is)"
    machines_json="$(python3 - <<PY
import json, glob
entries = []
for path in sorted(glob.glob("${machines_dir}/entry-*.json")):
    with open(path, encoding="utf-8") as f:
        entries.append(json.load(f))
print(json.dumps(entries, ensure_ascii=False))
PY
)"
    rm -rf "${machines_dir}"
    merge_physical_into_results "${machines_json}" "${tested}" "${iso_path}"
    hw_log "T1 matrix complete → ${RESULTS_JSON}"
    cat "${RESULTS_JSON}"
}

merge_entries() {
    local -a files=()
    if [[ -n "${STRAWWU_HW_T1_ENTRIES:-}" ]]; then
        # shellcheck disable=SC2206
        files=(${STRAWWU_HW_T1_ENTRIES})
    else
        hw_die "merge mode requires STRAWWU_HW_T1_ENTRIES"
    fi
    local entries_json tested iso_path
    tested="$(date -Is)"
    iso_path="$(resolve_iso_path 2>/dev/null || echo "")"
    entries_json="$(python3 - <<PY
import json, sys
entries = []
for path in ${files@Q}:
    with open(path, encoding="utf-8") as f:
        e = json.load(f)
    e.setdefault("tier", "T1")
    e["environment"] = e.get("environment") or "physical-live"
    entries.append(e)
print(json.dumps(entries, ensure_ascii=False))
PY
)"
    merge_physical_into_results "${entries_json}" "${tested}" "${iso_path}"
}

main() {
    local cmd="${1:-run}"
    case "${cmd}" in
        run) run_matrix ;;
        merge) merge_entries ;;
        -h|--help) usage; exit 0 ;;
        *) hw_die "unknown command: ${cmd}" ;;
    esac
}

main "$@"
