#!/usr/bin/env bash
# Preflight: ISO integrity + boot feasibility BEFORE QEMU boot-test.
# Blocks verification when artifacts are incomplete, inconsistent, or known-bad.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${REPO_ROOT}/os-image/work"
OUTPUT_DIR="${REPO_ROOT}/os-image/output"
VERSION="${STRAWWU_VERSION:-$(cat "${REPO_ROOT}/VERSION" 2>/dev/null || echo 0.4.0.0)}"
ISO_MODE="${STRAWWU_ISO_MODE:-release-iso}"
STRICT="${STRAWWU_PREFLIGHT_STRICT:-}"
if [[ -z "${STRICT}" ]]; then
  if [[ "${ISO_MODE}" == dev-iso ]]; then
    STRICT=0
  else
    STRICT=1
  fi
fi
ISO_NAME="StrawWU-${VERSION}-amd64.iso"
ISO_PATH="${OUTPUT_DIR}/${ISO_NAME}"
STAGING="${WORK_DIR}/iso-staging"
SPLICE="${REPO_ROOT}/os-image/scripts/initrd-splice.py"
MOUNT="${WORK_DIR}/.preflight-iso-mount"
FAIL=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "PASS: ${label}"
  else
    echo "FAIL: ${label}" >&2
    FAIL=1
  fi
}

warn() {
  echo "WARN: $*" >&2
}

squashfs_has_path() {
  local sq="$1" relpath="$2"
  local tmp
  tmp=$(mktemp -d)
  if unsquashfs -f -d "${tmp}" "${sq}" "${relpath}" 2>/dev/null && [[ -e "${tmp}/${relpath}" ]]; then
    rm -rf "${tmp}"
    return 0
  fi
  rm -rf "${tmp}"
  return 1
}

cleanup_mount() {
  if mountpoint -q "${MOUNT}" 2>/dev/null; then
    umount "${MOUNT}" 2>/dev/null || umount -l "${MOUNT}" 2>/dev/null || true
  fi
  rmdir "${MOUNT}" 2>/dev/null || true
}
trap cleanup_mount EXIT

echo "=== StrawWU ISO preflight (before boot-test) mode=${ISO_MODE} strict=${STRICT} ==="

# --- Build completion markers ---
check "build-iso marker exists" test -f "${WORK_DIR}/.build-iso-ok"
check "swap-kernel marker exists" test -f "${WORK_DIR}/.swap-kernel-ok"
if [[ -f "${WORK_DIR}/.swap-kernel-ok" ]]; then
  grep -q strawwu "${WORK_DIR}/.swap-kernel-ok" \
    && echo "PASS: swap-kernel references strawwu" \
    || { echo "FAIL: swap-kernel marker missing strawwu" >&2; FAIL=1; }
fi

# --- ISO file sanity ---
check "ISO file exists" test -f "${ISO_PATH}"
if [[ -f "${ISO_PATH}" ]]; then
  iso_bytes=$(stat -c%s "${ISO_PATH}")
  if [[ "${iso_bytes}" -ge 5000000000 ]]; then
    echo "PASS: ISO size ${iso_bytes} bytes (>= 5GB)"
  else
    echo "FAIL: ISO too small (${iso_bytes} bytes) — likely incomplete xorriso" >&2
    FAIL=1
  fi
fi

if [[ -f "${OUTPUT_DIR}/SHA256SUMS" && -f "${ISO_PATH}" ]]; then
  if (cd "${OUTPUT_DIR}" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
    echo "PASS: SHA256SUMS validates"
  else
    if [[ "${STRICT}" == "1" ]]; then
      echo "FAIL: SHA256SUMS mismatch — ISO corrupt or stale checksum" >&2
      FAIL=1
    else
      warn "SHA256SUMS mismatch — dev-iso allows continue"
    fi
  fi
else
  if [[ "${STRICT}" == "1" ]]; then
    warn "SHA256SUMS missing — release-iso should have checksums"
  else
    warn "SHA256SUMS missing — skipping checksum validation (dev-iso)"
  fi
fi

# --- Staging / ISO content checks ---
CASPER_DIR=""
INITRD_PATH=""
VMLINUZ_PATH=""
SQUASHFS_PATH=""

if [[ -d "${STAGING}/casper" ]]; then
  CASPER_DIR="${STAGING}/casper"
  echo "INFO: using iso-staging casper/"
elif [[ -f "${ISO_PATH}" ]]; then
  mkdir -p "${MOUNT}"
  if mount -o loop,ro "${ISO_PATH}" "${MOUNT}" 2>/dev/null; then
    CASPER_DIR="${MOUNT}/casper"
    echo "INFO: mounted ISO at ${MOUNT}"
  else
    echo "FAIL: cannot mount ISO for inspection" >&2
    FAIL=1
  fi
else
  echo "FAIL: no staging casper/ and no mountable ISO" >&2
  FAIL=1
fi

if [[ -n "${CASPER_DIR}" && -d "${CASPER_DIR}" ]]; then
  VMLINUZ_PATH="$(find "${CASPER_DIR}" -maxdepth 1 -name 'vmlinuz' -o -name 'vmlinuz*' 2>/dev/null | head -1)"
  INITRD_PATH="${CASPER_DIR}/initrd"
  SQUASHFS_PATH="${CASPER_DIR}/minimal.squashfs"

  check "casper vmlinuz exists" test -n "${VMLINUZ_PATH}" -a -f "${VMLINUZ_PATH}"
  check "casper initrd exists" test -f "${INITRD_PATH}"
  check "casper minimal.squashfs exists" test -f "${SQUASHFS_PATH}"

  if [[ -f "${VMLINUZ_PATH}" ]]; then
    rootfs_vmlinuz="$(find "${WORK_DIR}/rootfs/boot" -maxdepth 1 -name 'vmlinuz-*strawwu*' 2>/dev/null | head -1)"
    if [[ -n "${rootfs_vmlinuz}" && -f "${rootfs_vmlinuz}" ]] && cmp -s "${VMLINUZ_PATH}" "${rootfs_vmlinuz}"; then
      echo "PASS: casper vmlinuz matches rootfs strawwu kernel image"
    elif strings "${VMLINUZ_PATH}" 2>/dev/null | grep -qE '6\.8\.[0-9]+-strawwu|Linux version .*strawwu'; then
      echo "PASS: vmlinuz strings reference strawwu kernel"
    else
      echo "FAIL: casper vmlinuz does not match strawwu kernel (cmp/strings)" >&2
      FAIL=1
    fi
  fi

  if [[ -f "${INITRD_PATH}" ]]; then
    initrd_bytes=$(stat -c%s "${INITRD_PATH}")
    if [[ "${initrd_bytes}" -ge 30000000 && "${initrd_bytes}" -le 250000000 ]]; then
      echo "PASS: initrd size ${initrd_bytes} bytes (30M–250M)"
    elif [[ "${initrd_bytes}" -gt 250000000 ]]; then
      echo "FAIL: initrd bloated (${initrd_bytes} bytes) — likely bad module injection" >&2
      FAIL=1
    else
      echo "FAIL: initrd too small (${initrd_bytes} bytes)" >&2
      FAIL=1
    fi

    if [[ -x "${SPLICE}" || -f "${SPLICE}" ]]; then
      if python3 "${SPLICE}" verify "${INITRD_PATH}" >/dev/null 2>&1; then
        echo "PASS: initrd structure verify (initrd-splice)"
      else
        echo "FAIL: initrd structure verify failed" >&2
        FAIL=1
      fi
    fi

    # early3 modules must be strawwu, not upstream-only 6.11
    if command -v unmkinitramfs >/dev/null 2>&1; then
      early3_tmp=$(mktemp -d)
      if unmkinitramfs "${INITRD_PATH}" "${early3_tmp}" 2>/dev/null; then
        early3_dir="${early3_tmp}/early3"
        if [[ -d "${early3_dir}/usr/lib/modules" ]]; then
          mod_kvers=$(find "${early3_dir}/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)
          if echo "${mod_kvers}" | grep -q 'strawwu'; then
            echo "PASS: initrd early3 has strawwu modules"
          else
            echo "FAIL: initrd early3 missing strawwu modules (found: ${mod_kvers:-none})" >&2
            FAIL=1
          fi
          if echo "${mod_kvers}" | grep -q '6\.11\.0-17-generic' && ! echo "${mod_kvers}" | grep -q 'strawwu'; then
            echo "FAIL: initrd early3 still upstream 6.11-only modules" >&2
            FAIL=1
          fi
        else
          echo "FAIL: initrd early3 has no usr/lib/modules" >&2
          FAIL=1
        fi
        if find "${early3_dir}" -name 'isofs.ko*' -o -name 'iso9660.ko*' 2>/dev/null | grep -q .; then
          echo "PASS: initrd early3 has ISO filesystem module"
        else
          echo "FAIL: initrd early3 missing isofs/iso9660 module (CD mount will fail)" >&2
          FAIL=1
        fi
      else
        warn "unmkinitramfs failed — skipping early3 module checks"
      fi
      rm -rf "${early3_tmp}"
    fi
  fi

  if [[ -f "${SQUASHFS_PATH}" ]]; then
    sq_bytes=$(stat -c%s "${SQUASHFS_PATH}")
    sq_mtime=$(stat -c%Y "${SQUASHFS_PATH}")
    now=$(date +%s)
    age_days=$(( (now - sq_mtime) / 86400 ))

    if [[ "${sq_bytes}" -ge 2000000000 ]]; then
      echo "PASS: minimal.squashfs ${sq_bytes} bytes (>= 2GB branded)"
    elif [[ "${sq_bytes}" -le 1800000000 ]]; then
      if [[ "${STRICT}" == "1" ]]; then
        echo "FAIL: minimal.squashfs only ${sq_bytes} bytes — likely upstream 2025-02 old image (SKIP_SQUASHFS?)" >&2
        FAIL=1
      else
        warn "minimal.squashfs only ${sq_bytes} bytes — dev-iso may use smaller tree"
      fi
    else
      warn "minimal.squashfs ${sq_bytes} bytes — borderline size"
    fi

    if [[ "${age_days}" -le 7 ]]; then
      echo "PASS: minimal.squashfs mtime recent (${age_days}d old)"
    elif [[ "${STRICT}" == "1" ]]; then
      echo "FAIL: minimal.squashfs mtime ${age_days}d old — stale upstream squashfs?" >&2
      FAIL=1
    else
      warn "minimal.squashfs mtime ${age_days}d old (dev-iso relaxed)"
    fi

    if squashfs_has_path "${SQUASHFS_PATH}" "etc/systemd/system/strawwu-boot-marker.service"; then
      echo "PASS: squashfs contains strawwu-boot-marker.service"
    else
      echo "FAIL: squashfs missing strawwu-boot-marker.service" >&2
      FAIL=1
    fi

    if squashfs_has_path "${SQUASHFS_PATH}" "usr/share/plymouth/themes/strawwu-boot/strawwu-boot.plymouth"; then
      echo "PASS: squashfs contains strawwu-boot Plymouth theme"
    else
      echo "FAIL: squashfs missing strawwu-boot Plymouth theme" >&2
      FAIL=1
    fi

    if squashfs_has_path "${SQUASHFS_PATH}" "etc/systemd/system/multi-user.target.wants/strawwu-e2e-guest-runner.service"; then
      echo "FAIL: production squashfs must not enable strawwu-e2e-guest-runner (adds 4+ min boot delay)" >&2
      FAIL=1
    else
      echo "PASS: production squashfs has no install-e2e guest runner"
    fi

    if unsquashfs -cat "${SQUASHFS_PATH}" etc/gdm3/custom.conf 2>/dev/null | grep -q 'AutomaticLogin = ubuntu'; then
      echo "PASS: GDM live autologin configured for ubuntu"
    else
      echo "FAIL: GDM missing AutomaticLogin=ubuntu for live desktop" >&2
      FAIL=1
    fi
  fi
fi

# --- GRUB boot params (display + casper user) ---
grub_cfg=""
for candidate in \
  "${STAGING}/boot/grub/grub.cfg" \
  "${MOUNT}/boot/grub/grub.cfg"; do
  [[ -f "${candidate}" ]] && grub_cfg="${candidate}" && break
done

if [[ -n "${grub_cfg}" ]]; then
  if grep -q 'console=tty0' "${grub_cfg}"; then
    echo "PASS: GRUB has console=tty0 (physical display)"
  else
    echo "FAIL: GRUB missing console=tty0 — real hardware will show blank screen" >&2
    FAIL=1
  fi
  if grep -q 'username=ubuntu' "${grub_cfg}"; then
    echo "PASS: GRUB has username=ubuntu (casper live user)"
  else
    echo "FAIL: GRUB missing username=ubuntu — casper may use nonexistent strawwu user" >&2
    FAIL=1
  fi
else
  warn "GRUB cfg not found — skipping console/username checks"
fi

# --- Build mode marker ---
if [[ -f "${WORK_DIR}/.build-iso-mode" ]]; then
  built_mode=$(cat "${WORK_DIR}/.build-iso-mode")
  if [[ "${built_mode}" == "${ISO_MODE}" ]]; then
    echo "PASS: build mode matches preflight (${ISO_MODE})"
  else
    echo "FAIL: ISO built as ${built_mode} but preflight expects ${ISO_MODE}" >&2
    FAIL=1
  fi
else
  warn "missing .build-iso-mode marker"
fi

# --- Parallel build guard ---
if [[ "${STRAWWU_SKIP_SQUASHFS:-0}" == "1" ]]; then
  echo "FAIL: STRAWWU_SKIP_SQUASHFS=1 — fast repack must not enter boot-test pipeline" >&2
  FAIL=1
else
  echo "PASS: STRAWWU_SKIP_SQUASHFS=0 (full squashfs build)"
fi

HERMES_LOCK="/root/.hermes/locks/strawwu-build.lock"
if [[ -f "${HERMES_LOCK}" ]]; then
  holder=$(cat "${HERMES_LOCK}" 2>/dev/null || echo unknown)
  holder_pid=$(echo "${holder}" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
  if [[ -n "${holder_pid}" ]] && kill -0 "${holder_pid}" 2>/dev/null && [[ "${holder_pid}" -ne "$$" ]]; then
    echo "FAIL: build mutex held by live process pid=${holder_pid} — ISO may be mid-write" >&2
    FAIL=1
  else
    echo "PASS: build mutex free or stale (${holder})"
  fi
fi

# --- Residual QEMU (would corrupt boot-test) ---
_stray_qemu=0
while read -r _pid; do
  [[ -n "${_pid}" ]] || continue
  if tr '\0' ' ' < "/proc/${_pid}/cmdline" 2>/dev/null | grep -q 'StrawWU'; then
    _stray_qemu=1
    echo "FAIL: stray QEMU boot-test process pid=${_pid}" >&2
    tr '\0' ' ' < "/proc/${_pid}/cmdline" >&2
    echo >&2
  fi
done < <(pgrep -x qemu-system-x86_64 2>/dev/null || true)
if [[ "${_stray_qemu}" -eq 1 ]]; then
  echo "FAIL: stray QEMU boot-test processes running — clean before verify" >&2
  FAIL=1
else
  echo "PASS: no stray QEMU StrawWU processes"
fi

echo "=== ISO preflight done ==="
exit "${FAIL}"
