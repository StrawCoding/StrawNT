#!/usr/bin/env bash
# build.sh — Build linux-image-strawwu .deb from Ubuntu resolute kernel source + strawwu_ipc.
set -euo pipefail

KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${KERNEL_DIR}/.." && pwd)"
BUILD_DIR="${KERNEL_BUILD_DIR:-${KERNEL_DIR}/build}"
OUTPUT_DIR="${KERNEL_OUTPUT_DIR:-${KERNEL_DIR}/output}"
PATCH_DIR="${KERNEL_DIR}/patches"
MODULE_SRC="${KERNEL_DIR}/strawwu_ipc"
TARGET_JSON="${REPO_ROOT}/docs/plans/ubuntu-base-target.json"
ROOTFS_DIR="${STRAWWU_ROOTFS:-${REPO_ROOT}/os-image/work/rootfs}"
MOK_DIR="${STRAWWU_MOK_DIR:-${REPO_ROOT}/os-image/keys/secureboot}"
MOK_KEY="${MOK_DIR}/StrawWU-MOK.key"
MOK_CRT="${MOK_DIR}/StrawWU-MOK.crt"
MOK_CER="${MOK_DIR}/StrawWU-MOK.cer"

LOCAL_VERSION="${STRAWWU_LOCAL_VERSION:--strawwu}"
KERNEL_FLAVOR="${STRAWWU_KERNEL_FLAVOR:-generic}"
JOBS="${STRAWWU_KERNEL_JOBS:-$(nproc)}"
MARKER="${OUTPUT_DIR}/.build-ok"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

read_target_codename() {
    if [[ -f "${TARGET_JSON}" ]]; then
        python3 - "${TARGET_JSON}" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("active", {}).get("codename", "resolute"))
PY
    else
        echo "resolute"
    fi
}

# Single source of truth for the kernel ABI: docs/plans/ubuntu-base-target.json
# active.kernel_abi. Keeps build.sh, the Makefile, and the rootfs aligned.
read_target_kernel_abi() {
    if [[ -f "${TARGET_JSON}" ]]; then
        python3 - "${TARGET_JSON}" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("active", {}).get("kernel_abi", ""))
PY
    fi
}

detect_rootfs_kernel_abi() {
    local mod_dir kver
    mod_dir="$(ls -d "${ROOTFS_DIR}/lib/modules/"* 2>/dev/null | head -1 || true)"
    [[ -n "${mod_dir}" ]] || return 1
    kver="$(basename "${mod_dir}")"
    kver="${kver%-strawwu}"
    kver="${kver%-${KERNEL_FLAVOR}}"
    echo "${kver}"
}

UBUNTU_CODENAME="${STRAWWU_APT_SUITE:-$(read_target_codename)}"
# ABI resolution order: explicit override → rootfs detection → target JSON (single
# source of truth). No hardcoded literal fallback so the ABI never silently drifts
# from ubuntu-base-target.json.
KERNEL_ABI="${STRAWWU_KERNEL_ABI:-$(detect_rootfs_kernel_abi || true)}"
KERNEL_ABI="${KERNEL_ABI:-$(read_target_kernel_abi)}"
[[ -n "${KERNEL_ABI}" ]] || die "kernel ABI unresolved (set STRAWWU_KERNEL_ABI or active.kernel_abi in ${TARGET_JSON})"

need_cmd() {
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done
}

ensure_build_deps() {
    local missing=()
    for pkg in build-essential bc bison flex libelf-dev libssl-dev libncurses-dev \
        dwarves rsync devscripts equivs dpkg-dev python3 libdw-dev sbsigntool \
        openssl kmod zstd xz-utils; do
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed" \
            || missing+=("${pkg}")
    done
    if ((${#missing[@]})); then
        log "installing build deps: ${missing[*]}"
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    fi
}

ensure_deb_src_for_codename() {
    local codename="$1"
    local src_pkg="linux-source-${KERNEL_ABI%%-*}"
    if apt-cache policy "${src_pkg}" 2>/dev/null | grep -q 'Candidate:'; then
        return 0
    fi
    local marker="/etc/apt/sources.list.d/strawwu-kernel-src.sources"
    if [[ -f "${marker}" ]] && grep -q "Suites: ${codename}" "${marker}" 2>/dev/null; then
        apt-get update -qq
        return 0
    fi
    log "enabling deb-src for ${codename} (${src_pkg})"
    cat > "${marker}" <<EOF
Types: deb deb-src
URIs: http://archive.ubuntu.com/ubuntu/
Suites: ${codename} ${codename}-updates ${codename}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.ubuntu.com/ubuntu/
Suites: ${codename}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    apt-get update -qq
}

fetch_source() {
    local src_deb="linux-source-${KERNEL_ABI%%-*}"
    local tree="${BUILD_DIR}/linux-source"
    local stamp="${BUILD_DIR}/.source-abi"
    local abi_rev="${KERNEL_ABI##*-}"
    local src_ver="${KERNEL_ABI}.${abi_rev}"
    mkdir -p "${BUILD_DIR}"
    if [[ -d "${tree}" ]] && [[ -f "${stamp}" ]] && [[ "$(cat "${stamp}")" == "${KERNEL_ABI}" ]]; then
        log "reusing ${tree} (${KERNEL_ABI})"
        return
    fi
    log "fetching ${src_deb} for ABI ${KERNEL_ABI} (suite ${UBUNTU_CODENAME}, version ${src_ver})"
    rm -rf "${BUILD_DIR}"/linux-* "${stamp}"
    ensure_deb_src_for_codename "${UBUNTU_CODENAME}"
    # Only fetch the ABI-pinned source. Do NOT fall back to an unversioned
    # `apt-get source linux`: that would silently pull whatever version the mirror
    # currently ships and produce an ABI-mismatched kernel/modules.
    (
        cd "${BUILD_DIR}"
        apt-get source -y "linux=${src_ver}" 2>/dev/null \
            || apt-get source -y "${src_deb}=${src_ver}"
    ) || die "apt-get source failed for pinned version ${src_ver} (ABI ${KERNEL_ABI}); refusing unpinned fallback"
    local extracted
    extracted="$(find "${BUILD_DIR}" -maxdepth 1 -type d -name 'linux-*' ! -name 'linux-source' | sort | tail -1)"
    [[ -n "${extracted}" ]] || die "linux source tree not found under ${BUILD_DIR}"
    # Verify the fetched tree matches the requested ABI upstream base so a mismatch
    # is a hard error, not a subtly wrong build.
    local upstream_base="${KERNEL_ABI%%-*}"
    if [[ "$(basename "${extracted}")" != linux-"${upstream_base}"* ]]; then
        die "fetched source $(basename "${extracted}") does not match ABI ${KERNEL_ABI} (expected linux-${upstream_base}*)"
    fi
    ln -sfn "$(basename "${extracted}")" "${tree}"
    echo "${KERNEL_ABI}" > "${stamp}"
}

resolve_kernel_config() {
    local candidates=()
    candidates+=("/boot/config-${KERNEL_ABI}-${KERNEL_FLAVOR}")
    candidates+=("${ROOTFS_DIR}/boot/config-${KERNEL_ABI}-${KERNEL_FLAVOR}")
    if [[ -d "${ROOTFS_DIR}/boot" ]]; then
        while IFS= read -r cfg; do
            candidates+=("${cfg}")
        done < <(find "${ROOTFS_DIR}/boot" -maxdepth 1 -name 'config-*-generic' 2>/dev/null | sort -r)
    fi
    candidates+=("/boot/config-$(uname -r)")
    local cfg
    for cfg in "${candidates[@]}"; do
        if [[ -f "${cfg}" ]]; then
            echo "${cfg}"
            return 0
        fi
    done
    return 1
}

prepare_config() {
    local tree="${BUILD_DIR}/linux-source"
    local config_src
    config_src="$(resolve_kernel_config)" || die "kernel config not found for ABI ${KERNEL_ABI} (install linux-image-${KERNEL_ABI}-${KERNEL_FLAVOR} or clone resolute rootfs)"

    log "using config ${config_src}"
    cp "${config_src}" "${tree}/.config"
    make -C "${tree}" ARCH=x86_64 olddefconfig
    "${tree}/scripts/config" --file "${tree}/.config" --set-str LOCALVERSION "${LOCAL_VERSION}"
    "${tree}/scripts/config" --file "${tree}/.config" --module CONFIG_STRAWWU_IPC
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_OVERLAY_FS
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_ISO9660_FS
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_MODULE_SIG
    "${tree}/scripts/config" --file "${tree}/.config" --disable CONFIG_MODULE_SIG_ALL
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_SYSTEM_TRUSTED_KEYRING
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_SECONDARY_TRUSTED_KEYRING
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_INTEGRITY_PLATFORM_KEYRING
    "${tree}/scripts/config" --file "${tree}/.config" --enable CONFIG_LOAD_UEFI_KEYS
    "${tree}/scripts/config" --file "${tree}/.config" --set-str SYSTEM_TRUSTED_KEYS ""
    "${tree}/scripts/config" --file "${tree}/.config" --set-str SYSTEM_REVOCATION_KEYS ""
    make -C "${tree}" ARCH=x86_64 olddefconfig
    make -C "${tree}" ARCH=x86_64 syncconfig
    grep -qE '^CONFIG_STRAWWU_IPC=(m|y)' "${tree}/.config" \
        || die "CONFIG_STRAWWU_IPC not enabled in kernel config"
    grep -q '^CONFIG_MODULE_SIG=y' "${tree}/.config" \
        || die "CONFIG_MODULE_SIG not enabled"
    grep -q '^# CONFIG_MODULE_SIG_ALL is not set' "${tree}/.config" \
        || die "CONFIG_MODULE_SIG_ALL must stay disabled; modules use the persistent MOK"
}

validate_mok_material() {
    [[ -f "${MOK_KEY}" ]] || die "MOK private key missing: ${MOK_KEY}"
    [[ -f "${MOK_CRT}" ]] || die "MOK PEM certificate missing: ${MOK_CRT}"
    [[ -f "${MOK_CER}" ]] || die "MOK enrollment certificate missing: ${MOK_CER}"

    local key_pub cert_pub pem_fingerprint der_fingerprint
    key_pub="$(openssl pkey -in "${MOK_KEY}" -pubout -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)"
    cert_pub="$(openssl x509 -in "${MOK_CRT}" -pubkey -noout 2>/dev/null \
        | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)"
    [[ -n "${key_pub}" && "${key_pub}" == "${cert_pub}" ]] \
        || die "MOK private key does not match ${MOK_CRT}"

    pem_fingerprint="$(openssl x509 -in "${MOK_CRT}" -noout -fingerprint -sha256 | cut -d= -f2)"
    der_fingerprint="$(openssl x509 -inform DER -in "${MOK_CER}" -noout -fingerprint -sha256 | cut -d= -f2)"
    [[ "${pem_fingerprint}" == "${der_fingerprint}" ]] \
        || die "MOK PEM and enrollment certificates differ"
    MOK_FINGERPRINT="${pem_fingerprint}"
    export MOK_FINGERPRINT
}

sign_module_file() {
    local module="$1"
    local sign_file="$2"
    local hash="$3"
    local raw="${module}" tmp="" mode
    mode="$(stat -c '%a' "${module}")"

    case "${module}" in
        *.ko.zst)
            tmp="$(mktemp "${BUILD_DIR}/module-sign.XXXXXX.ko")"
            zstd -q -d -c "${module}" > "${tmp}"
            raw="${tmp}"
            ;;
        *.ko.xz)
            tmp="$(mktemp "${BUILD_DIR}/module-sign.XXXXXX.ko")"
            xz -d -c "${module}" > "${tmp}"
            raw="${tmp}"
            ;;
        *.ko.gz)
            tmp="$(mktemp "${BUILD_DIR}/module-sign.XXXXXX.ko")"
            gzip -d -c "${module}" > "${tmp}"
            raw="${tmp}"
            ;;
    esac

    "${sign_file}" "${hash}" "${MOK_KEY}" "${MOK_CRT}" "${raw}"
    case "${module}" in
        *.ko.zst) zstd -q -f -T0 "${raw}" -o "${module}" ;;
        *.ko.xz) xz -9 -C crc32 -c "${raw}" > "${module}" ;;
        *.ko.gz) gzip -n -9 -c "${raw}" > "${module}" ;;
    esac
    chmod "${mode}" "${module}"
    [[ -z "${tmp}" ]] || rm -f "${tmp}"
}

sign_kernel_modules() {
    local root="$1" kver="$2"
    local tree="${BUILD_DIR}/linux-source"
    local sign_file="${tree}/scripts/sign-file"
    local hash count=0 module signer
    [[ -x "${sign_file}" ]] || die "kernel sign-file helper missing: ${sign_file}"
    hash="$(sed -n 's/^CONFIG_MODULE_SIG_HASH="\([^"]*\)"/\1/p' "${tree}/.config")"
    hash="${hash:-sha512}"

    while IFS= read -r -d '' module; do
        sign_module_file "${module}" "${sign_file}" "${hash}"
        count=$((count + 1))
    done < <(find "${root}/lib/modules/${kver}" -type f \
        \( -name '*.ko' -o -name '*.ko.zst' -o -name '*.ko.xz' -o -name '*.ko.gz' \) -print0)
    [[ "${count}" -gt 0 ]] || die "no kernel modules found to sign for ${kver}"

    depmod -b "${root}" "${kver}"
    while IFS= read -r -d '' module; do
        signer="$(modinfo -F signer "${module}" 2>/dev/null || true)"
        [[ "${signer}" == *StrawWU* ]] || die "module is not signed by StrawWU MOK: ${module}"
    done < <(find "${root}/lib/modules/${kver}" -type f \
        \( -name '*.ko' -o -name '*.ko.zst' -o -name '*.ko.xz' -o -name '*.ko.gz' \) -print0)
    echo "${count}"
}

fix_kconfig_placement() {
    local kconfig="${1}/drivers/misc/Kconfig"
    python3 - "${kconfig}" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
block = (
    "config STRAWWU_IPC\n"
    '\ttristate "StrawWU kernel-userspace IPC stub"\n'
    "\tdefault m\n"
    "\thelp\n"
    "\t  StrawWU Phase 2 IPC stub (/dev/strawwu_ipc). Provides IOCTL\n"
    "\t  probe responses for userspace device proxy and anticheat stubs.\n"
    "\t  Not a Windows kernel driver loader.\n"
)
text = re.sub(r"\nconfig STRAWWU_IPC\n.*?(?=\nconfig |\nendmenu|\Z)", "\n", text, flags=re.S)
if "config STRAWWU_IPC" not in text:
    text = text.replace("\nendmenu\n", "\n" + block + "\nendmenu\n", 1)
p.write_text(text)
PY
}

ensure_strawwu_module() {
    local tree="${BUILD_DIR}/linux-source"
    local root="$1"
    local mod_kver ko_dst ko
    mod_kver="$(ls "${root}/lib/modules" 2>/dev/null | head -1)"
    [[ -n "${mod_kver}" ]] || die "no modules tree in repack root"
    ko_dst="${root}/lib/modules/${mod_kver}/kernel/drivers/misc/strawwu_ipc"
    if [[ -f "${ko_dst}/strawwu_ipc.ko" ]]; then
        return
    fi
    make -C "${tree}" ARCH=x86_64 syncconfig
    make -C "${tree}" ARCH=x86_64 M=drivers/misc/strawwu_ipc modules
    ko="$(find "${tree}/drivers/misc/strawwu_ipc" -name 'strawwu_ipc.ko' | head -1)"
    [[ -n "${ko}" ]] || die "strawwu_ipc.ko build failed"
    mkdir -p "${ko_dst}"
    cp "${ko}" "${ko_dst}/"
    if command -v depmod >/dev/null 2>&1; then
        depmod -b "${root}" "${mod_kver}" 2>/dev/null || true
    fi
    log "injected strawwu_ipc.ko into ${ko_dst}"
}

integrate_module() {
    local tree="${BUILD_DIR}/linux-source"
    local dest="${tree}/drivers/misc/strawwu_ipc"
    rm -rf "${dest}"
    mkdir -p "${dest}"
    cp "${MODULE_SRC}/strawwu_ipc.c" "${dest}/"
    cat > "${dest}/Makefile" <<'EOF'
obj-$(CONFIG_STRAWWU_IPC) += strawwu_ipc.o
EOF
    if ! grep -q 'strawwu_ipc/' "${tree}/drivers/misc/Makefile"; then
        patch -d "${tree}" -p1 < "${PATCH_DIR}/strawwu_ipc-kbuild.patch" || true
        grep -q 'strawwu_ipc/' "${tree}/drivers/misc/Makefile" \
            || echo 'obj-$(CONFIG_STRAWWU_IPC)	+= strawwu_ipc/' >> "${tree}/drivers/misc/Makefile"
    fi
    fix_kconfig_placement "${tree}"
}

build_debs() {
    local tree="${BUILD_DIR}/linux-source"
    if [[ "${STRAWWU_FORCE_KERNEL_BUILD:-0}" != "1" ]] \
        && find "${BUILD_DIR}" -maxdepth 1 -type f -name 'linux-image-*strawwu*.deb' ! -name '*dbg*' | grep -q .; then
        log "reusing existing linux-image-*strawwu*.deb (set STRAWWU_FORCE_KERNEL_BUILD=1 to rebuild)"
        return
    fi
    log "building kernel debs (jobs=${JOBS}) — this may take 20-60 minutes"
    if [[ "${STRAWWU_KERNEL_CLEAN:-0}" == "1" ]]; then
        log "STRAWWU_KERNEL_CLEAN=1 — removing prior kernel build outputs"
        make -C "${tree}" ARCH=x86_64 clean
    else
        log "continuing incremental kernel build (set STRAWWU_KERNEL_CLEAN=1 for a clean rebuild)"
    fi
    make -C "${tree}" ARCH=x86_64 -j"${JOBS}" bindeb-pkg \
        KDEB_CHANGELOG_DIST="strawwu"
}

repackage_strawwu_image() {
    mkdir -p "${OUTPUT_DIR}"
    local img_deb mod_deb
    img_deb="$(find "${BUILD_DIR}" -maxdepth 1 -type f -name "linux-image-*strawwu*.deb" \
        ! -name '*dbg*' | sort -V | tail -1)"
    mod_deb="$(find "${BUILD_DIR}" -maxdepth 1 -type f -name "linux-modules-*strawwu*.deb" \
        ! -name '*dbg*' ! -name '*extra*' | sort -V | tail -1)"
    [[ -n "${img_deb}" ]] || die "linux-image deb not found in ${BUILD_DIR}"

    local work="${BUILD_DIR}/repack"
    rm -rf "${work}"
    mkdir -p "${work}/root"
    dpkg-deb -R "${img_deb}" "${work}/root"
    if [[ -n "${mod_deb}" ]]; then
        dpkg-deb -R "${mod_deb}" "${work}/mod"
        cp -a "${work}/mod/boot/." "${work}/root/boot/"
        cp -a "${work}/mod/lib/." "${work}/root/lib/"
        if [[ -d "${work}/mod/usr" ]]; then
            cp -a "${work}/mod/usr/." "${work}/root/usr/"
        fi
    fi

    local kmod_tree mod_ko kmod_dest
    kmod_tree="$(ls -d "${work}/root/lib/modules/"* 2>/dev/null | head -1)"
    mod_ko="$(find "${BUILD_DIR}/linux-source" -path '*/strawwu_ipc/strawwu_ipc.ko' 2>/dev/null | head -1)"
    if [[ -n "${kmod_tree}" && -n "${mod_ko}" && ! -f "${kmod_tree}/kernel/drivers/misc/strawwu_ipc/strawwu_ipc.ko" ]]; then
        kmod_dest="${kmod_tree}/kernel/drivers/misc/strawwu_ipc"
        mkdir -p "${kmod_dest}"
        cp "${mod_ko}" "${kmod_dest}/"
        log "injected strawwu_ipc.ko into repackaged image"
    fi

    ensure_strawwu_module "${work}/root"

    local kver module_kver package_version product_version signed_modules custom_vmlinuz
    kver="$(grep -E '^Version:' "${work}/root/DEBIAN/control" | awk '{print $2}')"
    module_kver="$(find "${work}/root/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
    [[ -n "${module_kver}" ]] || die "packaged custom module tree missing"
    product_version="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
    package_version="${KERNEL_ABI}+strawwu${product_version}"
    sed -i 's/^Package: .*/Package: linux-image-strawwu/' "${work}/root/DEBIAN/control"
    sed -i "s/^Version: .*/Version: ${package_version}/" "${work}/root/DEBIAN/control"
    sed -i "s/^Description: .*/Description: StrawWU custom kernel image (${kver})/" "${work}/root/DEBIAN/control"
    sed -i '/^Depends:/s/, linux-modules-[^,)]*//g' "${work}/root/DEBIAN/control"
    sed -i '/^Depends:/s/linux-modules-[^,)]*, //g' "${work}/root/DEBIAN/control"

    signed_modules="$(sign_kernel_modules "${work}/root" "${module_kver}")"
    custom_vmlinuz="$(find "${work}/root/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | head -1)"
    [[ -n "${custom_vmlinuz}" ]] || die "packaged custom vmlinuz missing"
    STRAWWU_REQUIRE_MOK=1 STRAWWU_MOK_DIR="${MOK_DIR}" \
        bash "${REPO_ROOT}/os-image/scripts/secureboot-route/mok-sign.sh" "${custom_vmlinuz}"
    sbverify --cert "${MOK_CRT}" "${custom_vmlinuz}" >/dev/null 2>&1 \
        || die "packaged custom vmlinuz MOK verification failed"

    local out="${OUTPUT_DIR}/linux-image-strawwu_${package_version}_amd64.deb"
    rm -f "${OUTPUT_DIR}"/linux-image-strawwu_*.deb
    dpkg-deb -b "${work}/root" "${out}"
    log "produced ${out} (image+modules merged)"
    echo "${out}" > "${OUTPUT_DIR}/.kernel-deb-path"
    echo "${KERNEL_ABI}" > "${OUTPUT_DIR}/.kernel-abi"
    cat > "${OUTPUT_DIR}/.kernel-signing" <<EOF
module_sig=enabled
module_sig_all=disabled-explicit-mok-signing
kernel_image_signed_at_build=true
kernel_mok_signed=true
module_signer=StrawWU Secure Boot Machine Owner Key
module_count=${signed_modules}
mok_sha256=${MOK_FINGERPRINT}
abi=${KERNEL_ABI}
EOF
    date -Is > "${MARKER}"
}

main() {
    log "StrawWU kernel build: ABI=${KERNEL_ABI} suite=${UBUNTU_CODENAME} LOCALVERSION=${LOCAL_VERSION}"
    need_cmd make patch dpkg-deb apt-get python3
    ensure_build_deps
    need_cmd openssl sha256sum cut find modinfo depmod sbsign sbverify
    validate_mok_material
    fetch_source
    integrate_module
    prepare_config
    if [[ "${STRAWWU_SKIP_KERNEL_BUILD:-0}" != "1" ]]; then
        build_debs
    else
        log "STRAWWU_SKIP_KERNEL_BUILD=1 — skipping bindeb-pkg"
    fi
    repackage_strawwu_image
    log "kernel build complete"
}

main "$@"
