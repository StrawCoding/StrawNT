#!/usr/bin/env bash
# patch-iso-rescue-entry.sh — Add "StrawWU Rescue" GRUB/isolinux menu entry to ISO staging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ISO_STAGING="${WORK_DIR}/iso-staging"
RESCUE_LABEL="StrawWU Rescue"
RESCUE_PARAM="strawwu_rescue=1"

log() { echo "==> $*" >&2; }

already_patched() {
    local file="$1"
    [[ -f "${file}" ]] && grep -q "${RESCUE_LABEL}" "${file}"
}

patch_grub_cfg() {
    local cfg="$1"
    [[ -f "${cfg}" ]] || return 0
    if already_patched "${cfg}"; then
        log "rescue entry already present in ${cfg}"
        return 0
    fi

    python3 - "${cfg}" "${RESCUE_LABEL}" "${RESCUE_PARAM}" <<'PY'
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
label = sys.argv[2]
param = sys.argv[3]
text = cfg.read_text(encoding="utf-8")

if label in text:
    sys.exit(0)

# Clone the first menuentry block and add rescue kernel parameter.
match = re.search(
    r"(menuentry\s+['\"].*?StrawWU.*?['\"]\s*\{.*?\n\})",
    text,
    flags=re.DOTALL,
)
if not match:
    # Fallback: append a minimal rescue entry if no StrawWU menuentry found.
    block = f'''
menuentry '{label}' {{
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper {param} ---
    initrd /casper/initrd
}}
'''
    cfg.write_text(text.rstrip() + "\n" + block, encoding="utf-8")
    sys.exit(0)

template = match.group(1)
rescue = template
rescue = re.sub(
    r"menuentry\s+['\"][^'\"]+['\"]",
    f"menuentry '{label}'",
    rescue,
    count=1,
)
if f" {param}" not in rescue:
    rescue = re.sub(
        r"(linux\s+[^\n]+)",
        lambda m: m.group(1) + f" {param}",
        rescue,
        count=1,
    )
    rescue = re.sub(
        r"(append\s+[^\n]+)",
        lambda m: m.group(1) + f" {param}",
        rescue,
        count=1,
    )

insert_at = match.end()
cfg.write_text(text[:insert_at] + "\n" + rescue + text[insert_at:], encoding="utf-8")
PY
    log "patched rescue entry into ${cfg}"
}

patch_isolinux_txt() {
    local cfg="$1"
    [[ -f "${cfg}" ]] || return 0
    if already_patched "${cfg}"; then
        log "rescue entry already present in ${cfg}"
        return 0
    fi

    python3 - "${cfg}" "${RESCUE_LABEL}" "${RESCUE_PARAM}" <<'PY'
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
label = sys.argv[2]
param = sys.argv[3]
text = cfg.read_text(encoding="utf-8")

if label in text:
    sys.exit(0)

match = re.search(
    r"(label\s+\w+.*?)(?=label\s+\w+|\Z)",
    text,
    flags=re.DOTALL,
)
if not match:
    sys.exit(0)

template = match.group(1)
rescue = re.sub(r"^label\s+\w+", "label rescue", template, count=1, flags=re.MULTILINE)
rescue = re.sub(r"^\s*menu label.*$", f"  menu label {label}", rescue, count=1, flags=re.MULTILINE)
if param not in rescue:
    rescue = re.sub(
        r"^(\s*append\s+.*)$",
        lambda m: m.group(1) + f" {param}",
        rescue,
        count=1,
        flags=re.MULTILINE,
    )

insert_at = match.end()
cfg.write_text(text[:insert_at] + rescue + text[insert_at:], encoding="utf-8")
PY
    log "patched rescue entry into ${cfg}"
}

main() {
    [[ -d "${ISO_STAGING}" ]] || {
        log "iso-staging missing — skip rescue patch (source-only gate still valid)"
        exit 0
    }

    for cfg in \
        "${ISO_STAGING}/boot/grub/grub.cfg" \
        "${ISO_STAGING}/boot/grub/loopback.cfg" \
        "${ISO_STAGING}/isolinux/grub.cfg"; do
        patch_grub_cfg "${cfg}"
    done
    patch_isolinux_txt "${ISO_STAGING}/isolinux/txt.cfg"
    log "rescue ISO entry patch complete"
}

main "$@"
