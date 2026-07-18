#!/usr/bin/env bash
# patch-iso-secureboot-fallback.sh — Rewrite GRUB menuentries so the MOK-signed
# custom StrawWU kernel is tried first and, when Secure Boot rejects an unenrolled
# MOK ("bad shim lock signature"), boot falls back to the Canonical-signed generic
# kernel. Run AFTER console/rescue grub patches (final grub authority).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${STRAWWU_WORK_DIR:-${REPO_ROOT}/os-image/work}"
ISO_STAGING="${WORK_DIR}/iso-staging"

log() { echo "==> $*" >&2; }

patch_cfg() {
    local cfg="$1"
    [[ -f "${cfg}" ]] || return 0
    python3 - "${cfg}" <<'PY'
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
text = cfg.read_text(encoding="utf-8")

if "/casper/vmlinuz-generic" in text:
    # Already patched.
    sys.exit(0)

line_re = re.compile(
    r'^(?P<indent>[ \t]*)linux[ \t]+/casper/vmlinuz(?P<args>(?:[ \t][^\n]*)?)\n'
    r'(?P<iindent>[ \t]*)initrd[ \t]+/casper/initrd[ \t]*\n',
    flags=re.MULTILINE,
)

def repl(m):
    indent = m.group("indent")
    args = m.group("args") or ""
    inner = indent + "    "
    return (
        f'{indent}linux /casper/vmlinuz{args}\n'
        f'{indent}if [ "$?" = 0 ]; then\n'
        f'{inner}initrd /casper/initrd\n'
        f'{indent}else\n'
        f'{inner}echo "StrawWU: Secure Boot without enrolled MOK - booting signed fallback kernel"\n'
        f'{inner}linux /casper/vmlinuz-generic{args}\n'
        f'{inner}initrd /casper/initrd-generic\n'
        f'{indent}fi\n'
    )

new_text, n = line_re.subn(repl, text)
if n == 0:
    raise SystemExit(f"no custom kernel/initrd pair found in {cfg}")
cfg.write_text(new_text, encoding="utf-8")
print(f"patched {n} menuentr(ies) with Secure Boot fallback: {cfg}", file=sys.stderr)
PY
}

main() {
    [[ -d "${ISO_STAGING}" ]] || {
        log "iso-staging missing — skip Secure Boot fallback patch"
        exit 0
    }
    # Only rewrite grub to point at the fallback kernel when it was actually
    # staged; otherwise the menu would reference a non-existent
    # /casper/vmlinuz-generic and break boot.
    if [[ ! -f "${ISO_STAGING}/casper/vmlinuz-generic" || ! -f "${ISO_STAGING}/casper/initrd-generic" ]]; then
        log "no staged Secure Boot fallback kernel/initrd — skip fallback grub patch"
        exit 0
    fi
    for cfg in \
        "${ISO_STAGING}/boot/grub/grub.cfg" \
        "${ISO_STAGING}/boot/grub/loopback.cfg" \
        "${ISO_STAGING}/isolinux/grub.cfg"; do
        patch_cfg "${cfg}"
    done
    log "Secure Boot fallback grub patch complete"
}

main "$@"
