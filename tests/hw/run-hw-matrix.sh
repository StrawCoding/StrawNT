#!/usr/bin/env bash
# W8-HW-MATRIX: GPU/Wi-Fi/suspend/HiDPI hardware matrix — QEMU proxy + results v2.
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HW_DIR}/lib.sh"

main() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || hw_die "qemu-system-x86_64 not found"
    command -v python3 >/dev/null 2>&1 || hw_die "python3 not found"

    local iso_path
    iso_path="$(resolve_iso_path)"
    mkdir -p "${OUTPUT_DIR}"
    acquire_boot_lock "${iso_path}"

    hw_log "W8-HW-MATRIX — ISO=${iso_path} VERSION=${VERSION} schema=${MATRIX_SCHEMA}"

    local machines_dir
    machines_dir="$(mktemp -d)"
    local profile_idx=0

    save_result() {
        local entry="$1"
        profile_idx=$((profile_idx + 1))
        printf '%s\n' "${entry}" > "${machines_dir}/entry-${profile_idx}.json"
    }

    # Three profiles with HW dimension inference (std-vga + virtio-gpu variants).
    save_result "$(run_profile_boot \
        "hw-proxy-pc-bios" "pc" "legacy-bios" \
        "QEMU Virtual (pc/i440fx Legacy BIOS)" "std-vga" "2" \
        "${iso_path}" "" "" "1")"

    save_result "$(run_profile_boot \
        "hw-proxy-q35-uefi" "q35" "uefi" \
        "QEMU Virtual (q35 UEFI)" "virtio-gpu" "4" \
        "${iso_path}" "" "" "1")"

    save_result "$(run_profile_boot \
        "hw-proxy-q35-uefi-smp8" "q35" "uefi" \
        "QEMU Virtual (q35 UEFI 8-core)" "virtio-gpu" "8" \
        "${iso_path}" "" "" "1")"

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

    write_matrix_results "${VERSION}" "${machines_json}" "${tested}" "${iso_path}"

    hw_log "matrix complete → ${RESULTS_JSON}"
    cat "${RESULTS_JSON}"
}

main "$@"
