# Post-install serial marker for Calamares E2E (live host, dontChroot=true).
# Also emit desktop-ready alias for install-e2e harness.
set -eu
msg="STRAWWU-CALAMARES-INSTALL-OK"
printf '%s\n' "${msg}" | tee /dev/ttyS0 /dev/kmsg >/dev/null 2>&1 || true
