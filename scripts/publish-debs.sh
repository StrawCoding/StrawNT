#!/usr/bin/env bash
# publish-debs.sh — RE3+RE4: build signed StrawWU APT repository from .deb inputs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
SUITE="${STRAWWU_APT_SUITE:-noble}"
ARCH="${STRAWWU_APT_ARCH:-amd64}"
COMPONENT="${STRAWWU_APT_COMPONENT:-main}"
REPO_DIR="${STRAWWU_APT_REPO_DIR:-${REPO_ROOT}/os-image/output/apt-repo}"
SIGN_MODE="${STRAWWU_RELEASE_SIGN_MODE:-auto}"
GPG_KEY_ID="${STRAWWU_GPG_KEY_ID:-}"
ORIGIN="${STRAWWU_APT_ORIGIN:-StrawWU}"
LABEL="${STRAWWU_APT_LABEL:-StrawWU APT Repository}"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--check] [--deb-dir DIR]...

Build dists/${SUITE}/ + pool/ APT tree with Packages.gz and signed Release.

Environment:
  STRAWWU_APT_REPO_DIR     Output repo root (default: os-image/output/apt-repo)
  STRAWWU_VERSION          Package version filter (default: VERSION file)
  STRAWWU_APT_SUITE        Suite name (default: noble)
  STRAWWU_APT_ARCH         Binary arch (default: amd64)
  STRAWWU_GPG_KEY_ID       GPG key for Release.gpg
  STRAWWU_RELEASE_SIGN_MODE  auto | required | skip
EOF
}

detect_gpg_key() {
    if [[ -n "${GPG_KEY_ID}" ]]; then
        local key="${GPG_KEY_ID}"
        key="${key##*/}"
        echo "${key}"
        return 0
    fi
    if ! command -v gpg >/dev/null 2>&1; then
        return 1
    fi
    local list key=""
    list="$(mktemp)"
    gpg --list-secret-keys --keyid-format=long 2>/dev/null > "${list}" || true
    while IFS= read -r line; do
        if [[ "${line}" =~ ^sec ]]; then
            key="${line##*/}"
            key="${key%% *}"
        elif [[ -n "${key}" && "${line}" =~ ^uid ]] && echo "${line}" | grep -Eqi 'strawwu|apt@test\.strawwu'; then
            rm -f "${list}"
            echo "${key}"
            return 0
        fi
    done < "${list}"
    rm -f "${list}"
    return 1
}

gpg_available() { command -v gpg >/dev/null 2>&1; }

pool_letter() {
    local name="$1"
    echo "${name:0:1}"
}

collect_debs() {
    local -a inputs=("$@")
    local dir deb tmp
    tmp="$(mktemp)"

    if [[ ${#inputs[@]} -eq 0 ]]; then
        inputs=(
            "${REPO_ROOT}/os-image/debs"
            "${REPO_ROOT}/packaging/output"
        )
    fi
    : > "${tmp}"
    for dir in "${inputs[@]}"; do
        [[ -d "${dir}" ]] || continue
        if [[ "${dir}" == *"/debs" ]]; then
            find "${dir}" -path '*/output/*.deb' -type f 2>/dev/null >> "${tmp}" || true
        else
            find "${dir}" -maxdepth 1 -name '*.deb' -type f 2>/dev/null >> "${tmp}" || true
        fi
    done
    sort -u "${tmp}" | while IFS= read -r deb; do
        [[ -n "${deb}" && "${deb}" == *"_${VERSION}_"* ]] && echo "${deb}"
    done
    rm -f "${tmp}"
}

install_pool() {
    local deb="$1"
    local base pkg first dest
    base="$(basename "${deb}")"
    pkg="${base%%_*}"
    first="$(pool_letter "${pkg}")"
    dest="${REPO_DIR}/pool/${COMPONENT}/${first}/${pkg}/${base}"
    mkdir -p "$(dirname "${dest}")"
    cp -a "${deb}" "${dest}"
    echo "${dest}"
}

check_prereqs() {
    command -v apt-ftparchive >/dev/null 2>&1 || die "apt-ftparchive not found"
    command -v dpkg-scanpackages >/dev/null 2>&1 || die "dpkg-scanpackages not found"
    [[ -d "${REPO_DIR}" || true ]]
}

build_repo() {
    local -a deb_dirs=("$@")
    local -a debs=()
    local deb dist_binary packages release deb_list

    deb_list="$(mktemp)"
    collect_debs "${deb_dirs[@]}" > "${deb_list}"
    mapfile -t debs < "${deb_list}"
    rm -f "${deb_list}"

    if [[ ${#debs[@]} -eq 0 ]]; then
        die "no .deb files for version ${VERSION}"
    fi

    log "publishing ${#debs[@]} package(s) to ${REPO_DIR}"
    rm -rf "${REPO_DIR}"
    mkdir -p "${REPO_DIR}/pool" "${REPO_DIR}/dists/${SUITE}"

    for deb in "${debs[@]}"; do
        install_pool "${deb}" >/dev/null
    done

    dist_binary="${REPO_DIR}/dists/${SUITE}/${COMPONENT}/binary-${ARCH}"
    mkdir -p "${dist_binary}"

    packages="${dist_binary}/Packages"
    cat > "${REPO_DIR}/apt-ftparchive.conf" <<EOF
Dir {
  ArchiveDir ".";
  CacheDir "/tmp";
  LogDir "/tmp";
};

APT::FTPArchive::Release::Origin "${ORIGIN}";
APT::FTPArchive::Release::Label "${LABEL}";
APT::FTPArchive::Release::Suite "${SUITE}";
APT::FTPArchive::Release::Codename "${SUITE}";
APT::FTPArchive::Release::Architectures "${ARCH}";
APT::FTPArchive::Release::Components "${COMPONENT}";
EOF

    (
        cd "${REPO_DIR}"
        dpkg-scanpackages pool /dev/null > "dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages"
        gzip -9kf "dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages"
        apt-ftparchive -c apt-ftparchive.conf release "dists/${SUITE}" > "dists/${SUITE}/Release"
    )

    release="${REPO_DIR}/dists/${SUITE}/Release"

    local key=""
    if [[ "${SIGN_MODE}" != "skip" ]]; then
        if key="$(detect_gpg_key)"; then
            log "GPG signing Release with ${key}"
            gpg --batch --yes --local-user "${key}" --armor --detach-sign \
                --output "${REPO_DIR}/dists/${SUITE}/Release.gpg" "${release}"
        elif [[ "${SIGN_MODE}" == "required" ]]; then
            die "GPG signing required but no StrawWU secret key found"
        else
            warn "no StrawWU GPG key — Release unsigned (dev/nightly)"
        fi
    fi

    printf '%s\n' "${VERSION}" > "${REPO_DIR}/.strawwu-apt-version"
    log "APT repo ready at ${REPO_DIR}"
    find "${REPO_DIR}/dists" "${REPO_DIR}/pool" -type f | sort
}

main() {
    local mode="publish"
    local -a deb_dirs=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                mode="check"
                shift
                ;;
            --deb-dir)
                deb_dirs+=("$2")
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                deb_dirs+=("$1")
                shift
                ;;
        esac
    done

    case "${mode}" in
        check)
            check_prereqs
            log "publish-debs prerequisites OK"
            ;;
        publish)
            check_prereqs
            build_repo "${deb_dirs[@]}"
            ;;
    esac
}

main "$@"
