#!/usr/bin/env bash
# release-sign.sh — RE2: SHA256SUMS + detached GPG signatures for release artifacts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${STRAWWU_OUTPUT_DIR:-${REPO_ROOT}/os-image/output}"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
SIGN_MODE="${STRAWWU_RELEASE_SIGN_MODE:-auto}"
GPG_KEY_ID="${STRAWWU_GPG_KEY_ID:-}"
ISO_NAME="StrawWU-${VERSION}-amd64.iso"

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--check] [--all-isos]

Environment:
  STRAWWU_OUTPUT_DIR       Artifact directory (default: os-image/output)
  STRAWWU_VERSION          Release version (default: VERSION file)
  STRAWWU_RELEASE_SIGN_MODE  auto | required | skip
  STRAWWU_GPG_KEY_ID       GPG key id/fingerprint (auto-detect strawwu key)

Modes:
  auto      Sign when a StrawWU secret key is available; otherwise SHA256 only
  required  Fail if signing cannot be performed
  skip      Generate SHA256SUMS only (no GPG)
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
        elif [[ -n "${key}" && "${line}" =~ ^uid ]] && echo "${line}" | grep -qi strawwu; then
            rm -f "${list}"
            echo "${key}"
            return 0
        fi
    done < "${list}"
    rm -f "${list}"
    return 1
}

gpg_available() {
    command -v gpg >/dev/null 2>&1
}

sign_file() {
    local file="$1"
    local key="$2"
    log "GPG signing ${file}"
    gpg --batch --yes --local-user "${key}" --armor --detach-sign \
        --output "${file}.asc" "${file}"
}

check_prereqs() {
    [[ -d "${OUTPUT_DIR}" ]] || die "missing output dir ${OUTPUT_DIR}"
    if [[ "${SIGN_MODE}" != "skip" ]] && ! gpg_available; then
        if [[ "${SIGN_MODE}" == "required" ]]; then
            die "gpg not found (STRAWWU_RELEASE_SIGN_MODE=required)"
        fi
        warn "gpg not found — SHA256 only"
        return 0
    fi
    if [[ "${SIGN_MODE}" == "required" ]] && [[ -z "$(detect_gpg_key || true)" ]]; then
        die "no StrawWU GPG secret key (set STRAWWU_GPG_KEY_ID)"
    fi
    pass_msg="release-sign prerequisites OK (mode=${SIGN_MODE})"
    echo "${pass_msg}"
}

collect_isos() {
    if [[ "${SIGN_ALL_ISOS:-0}" == "1" ]]; then
        find "${OUTPUT_DIR}" -maxdepth 1 -name 'StrawWU-*.iso' -printf '%f\n' | sort
    elif [[ -f "${OUTPUT_DIR}/${ISO_NAME}" ]]; then
        echo "${ISO_NAME}"
    else
        find "${OUTPUT_DIR}" -maxdepth 1 -name 'StrawWU-*.iso' -printf '%f\n' | sort | tail -1
    fi
}

main() {
    local check_only=0
    SIGN_ALL_ISOS=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=1; shift ;;
            --all-isos) SIGN_ALL_ISOS=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    if [[ "${check_only}" -eq 1 ]]; then
        check_prereqs
        exit 0
    fi

    mkdir -p "${OUTPUT_DIR}"
    local isos
    isos="$(collect_isos)"
    [[ -n "${isos}" ]] || die "no StrawWU-*.iso in ${OUTPUT_DIR}"

    local iso
    local sums=()
    while IFS= read -r iso; do
        [[ -n "${iso}" ]] || continue
        [[ -f "${OUTPUT_DIR}/${iso}" ]] || die "missing ${OUTPUT_DIR}/${iso}"
        sums+=("${iso}")
    done <<< "${isos}"

    (
        cd "${OUTPUT_DIR}"
        sha256sum "${sums[@]}" > SHA256SUMS
    )
    log "SHA256SUMS written (${#sums[@]} artifact(s))"

    if [[ "${SIGN_MODE}" == "skip" ]]; then
        warn "STRAWWU_RELEASE_SIGN_MODE=skip — no GPG signatures"
    else
        local key=""
        key="$(detect_gpg_key || true)"
        if [[ -z "${key}" ]]; then
            if [[ "${SIGN_MODE}" == "required" ]]; then
                die "no StrawWU GPG secret key available"
            fi
            warn "no StrawWU GPG key — SHA256SUMS only (set STRAWWU_GPG_KEY_ID to sign)"
        else
            sign_file "${OUTPUT_DIR}/SHA256SUMS" "${key}"
            for iso in "${sums[@]}"; do
                sign_file "${OUTPUT_DIR}/${iso}" "${key}"
            done
            log "GPG signatures created (key ${key})"
        fi
    fi

    bash "${REPO_ROOT}/scripts/generate-release-manifest.sh"
}

main "$@"
