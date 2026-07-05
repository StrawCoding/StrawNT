#!/usr/bin/env bash
# sync-firstboot-overlay.sh — Stage current strawwu-firstboot into 9p guest share for E2E.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEB_ROOT="${REPO_ROOT}/os-image/debs/strawwu-firstboot"
OVERLAY="${GUEST_SHARE}/firstboot-e2e-overlay"

main() {
    mkdir -p "${OVERLAY}/usr/lib/strawwu-firstboot" "${OVERLAY}/usr/bin"
    for f in core.py i18n.py wizard_gtk4.py; do
        [[ -f "${DEB_ROOT}/usr/lib/strawwu-firstboot/${f}" ]] \
            || die "missing ${DEB_ROOT}/usr/lib/strawwu-firstboot/${f}"
        cp -f "${DEB_ROOT}/usr/lib/strawwu-firstboot/${f}" \
            "${OVERLAY}/usr/lib/strawwu-firstboot/${f}"
    done
    cp -f "${DEB_ROOT}/usr/bin/strawwu-firstboot" "${OVERLAY}/usr/bin/strawwu-firstboot"
    chmod 755 "${OVERLAY}/usr/bin/strawwu-firstboot"
    grep -q 'run_e2e' "${OVERLAY}/usr/lib/strawwu-firstboot/core.py" \
        || die "overlay core.py missing run_e2e"
    grep -q 'FIRSTBOOT_OK' "${OVERLAY}/usr/lib/strawwu-firstboot/core.py" \
        || die "overlay core.py missing FIRSTBOOT_OK marker"
    log "firstboot E2E overlay synced → ${OVERLAY}"
}

main "$@"
