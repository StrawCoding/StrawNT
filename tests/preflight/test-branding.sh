#!/usr/bin/env bash
# Preflight: StrawWU branding overlay static checks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRANDING="${REPO_ROOT}/os-image/config/branding"
FAIL=0

check() {
    if "$@"; then
        echo "PASS: $*"
    else
        echo "FAIL: $*"
        FAIL=1
    fi
}

echo "=== StrawWU branding preflight ==="

check test -f "${BRANDING}/etc/os-release"
check test -f "${BRANDING}/usr/share/plymouth/themes/strawwu-boot/logo.png"
check test -f "${BRANDING}/source/strawwu-logo-icon.png"
check test -f "${BRANDING}/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth"
check test -f "${BRANDING}/usr/local/sbin/strawwu-boot-selfcheck"
check test -f "${BRANDING}/etc/systemd/system/strawwu-boot-selfcheck.service"
check test -f "${BRANDING}/usr/share/calamares/branding/strawwu/branding.desc"
check test -x "${REPO_ROOT}/os-image/scripts/apply-branding.sh" || chmod +x "${REPO_ROOT}/os-image/scripts/apply-branding.sh"

if grep -q 'NAME="StrawWU"' "${BRANDING}/etc/os-release"; then
    echo "PASS: os-release NAME=StrawWU"
else
    echo "FAIL: os-release missing NAME=StrawWU"
    FAIL=1
fi

if grep -qi 'ubuntu' "${BRANDING}/etc/os-release" && ! grep -q '^ID=ubuntu$' "${BRANDING}/etc/os-release"; then
    echo "FAIL: os-release still contains Ubuntu (except ID=ubuntu for casper)"
    FAIL=1
elif grep -q '^NAME="Ubuntu"' "${BRANDING}/etc/os-release" || grep -q '^PRETTY_NAME="Ubuntu' "${BRANDING}/etc/os-release"; then
    echo "FAIL: os-release still shows Ubuntu branding"
    FAIL=1
else
    echo "PASS: os-release branding OK (ID=ubuntu allowed for casper live boot)"
fi

check test -f "${BRANDING}/etc/casper.conf"
if grep -q 'USERNAME="ubuntu"' "${BRANDING}/etc/casper.conf"; then
    echo "PASS: casper.conf pins live USERNAME=ubuntu"
else
    echo "FAIL: casper.conf must export USERNAME=ubuntu"
    FAIL=1
fi

if grep -q 'ModuleName=two-step' "${BRANDING}/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth"; then
    echo "PASS: plymouth theme uses two-step module"
else
    echo "FAIL: plymouth theme module"
    FAIL=1
fi

if grep -q 'UseProgressBar=true' "${BRANDING}/usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth"; then
    echo "PASS: plymouth boot progress bar enabled"
else
    echo "FAIL: plymouth missing UseProgressBar"
    FAIL=1
fi

check test -f "${BRANDING}/usr/share/calamares/branding/strawwu/strawwu-logo-icon.png"

for forbidden in partition.conf welcome.conf settings.conf devices.conf; do
    if [[ -f "${BRANDING}/etc/calamares/${forbidden}" ]]; then
        echo "FAIL: branding must not ship calamares ${forbidden}"
        FAIL=1
    fi
done
echo "PASS: no forbidden calamares overrides in branding"

echo "--- desktop theme checks ---"
check test -d "${BRANDING}/usr/share/themes/StrawWU-Dark"
check test -f "${BRANDING}/usr/share/themes/StrawWU-Dark/index.theme"
check test -f "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-4.0/gtk.css"
check test -f "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-3.0/gtk.css"
check test -f "${BRANDING}/usr/share/themes/StrawWU-Dark/gnome-shell/gnome-shell.css"

check test -f "${BRANDING}/usr/share/backgrounds/strawwu/strawwu-wallpaper-dark.png"
check test -f "${BRANDING}/usr/share/backgrounds/strawwu/strawwu-wallpaper-light.png"
check test -f "${BRANDING}/usr/share/gnome-background-properties/strawwu-wallpapers.xml"

check test -f "${BRANDING}/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg"

OVERRIDE="${BRANDING}/usr/share/glib-2.0/schemas/99_strawwu-branding.gschema.override"
check test -f "${OVERRIDE}"
if grep -q "gtk-theme='StrawWU-Dark'" "${OVERRIDE}"; then
    echo "PASS: gschema override sets StrawWU-Dark theme"
else
    echo "FAIL: gschema override missing StrawWU-Dark theme"
    FAIL=1
fi
if grep -q "color-scheme='prefer-dark'" "${OVERRIDE}"; then
    echo "PASS: gschema override enables dark mode"
else
    echo "FAIL: gschema override missing dark mode"
    FAIL=1
fi
if grep -q "strawwu-wallpaper-dark" "${OVERRIDE}"; then
    echo "PASS: gschema override sets StrawWU wallpaper"
else
    echo "FAIL: gschema override missing wallpaper"
    FAIL=1
fi

echo "=== branding preflight done ==="
exit "${FAIL}"
