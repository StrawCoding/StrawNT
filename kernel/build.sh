#!/usr/bin/env bash
# build.sh — Build linux-image-strawwu .deb from Ubuntu noble kernel source + strawwu_ipc.
set -euo pipefail

KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${KERNEL_DIR}/.." && pwd)"
BUILD_DIR="${KERNEL_BUILD_DIR:-${KERNEL_DIR}/build}"
OUTPUT_DIR="${KERNEL_OUTPUT_DIR:-${KERNEL_DIR}/output}"
PATCH_DIR="${KERNEL_DIR}/patches"
MODULE_SRC="${KERNEL_DIR}/strawwu_ipc"

# Match noble live ISO / host generic ABI.
KERNEL_ABI="${STRAWWU_KERNEL_ABI:-6.8.0-124}"
KERNEL_FLAVOR="${STRAWWU_KERNEL_FLAVOR:-generic}"
LOCAL_VERSION="${STRAWWU_LOCAL_VERSION:--strawwu}"
JOBS="${STRAWWU_KERNEL_JOBS:-$(nproc)}"
MARKER="${OUTPUT_DIR}/.build-ok"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done
}

ensure_build_deps() {
    local missing=()
    for pkg in build-essential bc bison flex libelf-dev libssl-dev libncurses-dev \
        dwarves rsync devscripts equivs dpkg-dev; do
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed" \
            || missing+=("${pkg}")
    done
    if ((${#missing[@]})); then
        log "installing build deps: ${missing[*]}"
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    fi
}

enable_deb_src() {
    if apt-cache policy linux-source-6.8.0 2>/dev/null | grep -q 'Candidate:'; then
        if ! grep -q 'Types: deb-src' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
            log "enabling deb-src in ubuntu.sources"
            cat >> /etc/apt/sources.list.d/ubuntu.sources <<'EOF'

Types: deb-src
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb-src
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
            apt-get update -qq
        fi
    fi
}

fetch_source() {
    local src_deb="linux-source-${KERNEL_ABI%%-*}"
    local tree="${BUILD_DIR}/linux-source"
    local stamp="${BUILD_DIR}/.source-abi"
    mkdir -p "${BUILD_DIR}"
    if [[ -d "${tree}" ]] && [[ -f "${stamp}" ]] && [[ "$(cat "${stamp}")" == "${KERNEL_ABI}" ]]; then
        log "reusing ${tree} (${KERNEL_ABI})"
        return
    fi
    log "fetching ${src_deb} for ABI ${KERNEL_ABI}"
    rm -rf "${BUILD_DIR}"/linux-* "${stamp}"
    enable_deb_src
    (
        cd "${BUILD_DIR}"
        apt-get source -y "linux=${KERNEL_ABI}.${KERNEL_ABI##*-}" 2>/dev/null \
            || apt-get source -y "${src_deb}=${KERNEL_ABI}.${KERNEL_ABI##*-}" 2>/dev/null \
            || apt-get source -y "${src_deb}"
    )
    local extracted
    extracted="$(find "${BUILD_DIR}" -maxdepth 1 -type d -name 'linux-*' ! -name 'linux-source' | sort | tail -1)"
    [[ -n "${extracted}" ]] || die "linux source tree not found under ${BUILD_DIR}"
    ln -sfn "$(basename "${extracted}")" "${tree}"
    echo "${KERNEL_ABI}" > "${stamp}"
}

prepare_config() {
    local tree="${BUILD_DIR}/linux-source"
    local config_src="/boot/config-${KERNEL_ABI}-${KERNEL_FLAVOR}"
    [[ -f "${config_src}" ]] || config_src="/boot/config-$(uname -r)"
    [[ -f "${config_src}" ]] || die "kernel config not found (install linux-image-${KERNEL_ABI}-${KERNEL_FLAVOR})"

    log "using config ${config_src}"
    cp "${config_src}" "${tree}/.config"
    make -C "${tree}" ARCH=x86_64 olddefconfig
    "${tree}/scripts/config" --file "${tree}/.config" --set-str LOCALVERSION "${LOCAL_VERSION}"
    "${tree}/scripts/config" --file "${tree}/.config" --module CONFIG_STRAWWU_IPC
    "${tree}/scripts/config" --file "${tree}/.config" --disable CONFIG_MODULE_SIG
    "${tree}/scripts/config" --file "${tree}/.config" --disable CONFIG_SYSTEM_TRUSTED_KEYRING
    "${tree}/scripts/config" --file "${tree}/.config" --set-str SYSTEM_TRUSTED_KEYS ""
    "${tree}/scripts/config" --file "${tree}/.config" --set-str SYSTEM_REVOCATION_KEYS ""
    make -C "${tree}" ARCH=x86_64 olddefconfig
    make -C "${tree}" ARCH=x86_64 syncconfig
    grep -qE '^CONFIG_STRAWWU_IPC=(m|y)' "${tree}/.config" \
        || die "CONFIG_STRAWWU_IPC not enabled in kernel config"
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
    # Clean stale objects from failed partial builds; keep .config.
    make -C "${tree}" ARCH=x86_64 clean
    # LOCALVERSION already in .config — do not pass again (would double-append)
    make -C "${tree}" ARCH=x86_64 -j"${JOBS}" bindeb-pkg \
        KDEB_CHANGELOG_DIST="strawwu"
}

repackage_strawwu_image() {
    mkdir -p "${OUTPUT_DIR}"
    local img_deb mod_deb
    img_deb="$(find "${BUILD_DIR}" -maxdepth 1 -type f -name "linux-image-*strawwu*.deb" \
        ! -name '*dbg*' | head -1)"
    mod_deb="$(find "${BUILD_DIR}" -maxdepth 1 -type f -name "linux-modules-*strawwu*.deb" \
        ! -name '*dbg*' ! -name '*extra*' | head -1)"
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

    # Ensure strawwu_ipc.ko is present (bindeb-pkg may omit late-built misc modules).
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

    local kver
    kver="$(grep -E '^Version:' "${work}/root/DEBIAN/control" | awk '{print $2}')"
    sed -i 's/^Package: .*/Package: linux-image-strawwu/' "${work}/root/DEBIAN/control"
    sed -i "s/^Description: .*/Description: StrawWU custom kernel image (${kver})/" "${work}/root/DEBIAN/control"
    # Bundled modules — drop split-package Depends so chroot apt install succeeds.
    sed -i '/^Depends:/s/, linux-modules-[^,)]*//g' "${work}/root/DEBIAN/control"
    sed -i '/^Depends:/s/linux-modules-[^,)]*, //g' "${work}/root/DEBIAN/control"

    local out="${OUTPUT_DIR}/linux-image-strawwu_${kver}_amd64.deb"
    rm -f "${out}"
    dpkg-deb -b "${work}/root" "${out}"
    log "produced ${out} (image+modules merged)"
    echo "${out}" > "${OUTPUT_DIR}/.kernel-deb-path"
    date -Is > "${MARKER}"
}

main() {
    need_cmd make patch dpkg-deb apt-get
    ensure_build_deps
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
