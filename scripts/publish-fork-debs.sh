#!/usr/bin/env bash
# publish-fork-debs.sh — Publish fork upstream package debs to the strawwu-fork APT suite.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=os-image/scripts/lib/fork-apt-env.sh
source "${REPO_ROOT}/os-image/scripts/lib/fork-apt-env.sh"
load_fork_apt_env "${REPO_ROOT}"

PUBLISH="${REPO_ROOT}/scripts/publish-debs.sh"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
DEB_INPUT="${STRAWWU_FORK_PACKAGES_OUTPUT}"
ALLOW_EMPTY=0

log() { echo "==> $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--check] [--allow-empty] [--deb-dir DIR]

Publish built fork package .debs to dists/${STRAWWU_FORK_APT_SUITE}/ + pool/.

Environment:
  STRAWWU_FORK_APT_SUITE      Suite codename (default: strawwu-fork)
  STRAWWU_FORK_APT_REPO_DIR   Output repo root (default: os-image/output/apt-fork-repo)
  STRAWWU_FORK_PACKAGES_OUTPUT  Input deb directory (default: fork/packages/output)
  STRAWWU_VERSION             Package version filter (default: VERSION file)
EOF
}

count_version_debs() {
  local dir="$1"
  find "${dir}" -maxdepth 1 -name "*_${VERSION}_*.deb" -type f 2>/dev/null | wc -l
}

main() {
    local mode="publish"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                mode="check"
                shift
                ;;
            --allow-empty)
                ALLOW_EMPTY=1
                shift
                ;;
            --deb-dir)
                DEB_INPUT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                DEB_INPUT="$1"
                shift
                ;;
        esac
    done

    [[ -x "${PUBLISH}" || -f "${PUBLISH}" ]] || die "missing publish-debs.sh: ${PUBLISH}"

    case "${mode}" in
        check)
            bash "${PUBLISH}" --check
            log "publish-fork-debs prerequisites OK (suite=${STRAWWU_FORK_APT_SUITE})"
            ;;
        publish)
            [[ -d "${DEB_INPUT}" ]] || die "fork deb input missing: ${DEB_INPUT}"
            local count
            count="$(count_version_debs "${DEB_INPUT}")"
            if [[ "${count}" -eq 0 ]]; then
                if [[ "${ALLOW_EMPTY}" -eq 1 ]]; then
                    log "no fork debs for version ${VERSION} (allow-empty)"
                    exit 0
                fi
                die "no fork .deb files for version ${VERSION} in ${DEB_INPUT} (run make build-fork-packages first)"
            fi

            log "publishing ${count} fork deb(s) to suite ${STRAWWU_FORK_APT_SUITE}"
            export STRAWWU_APT_SUITE="${STRAWWU_FORK_APT_SUITE}"
            export STRAWWU_APT_REPO_DIR="${STRAWWU_FORK_APT_REPO_DIR}"
            export STRAWWU_APT_ORIGIN="${STRAWWU_FORK_APT_ORIGIN:-StrawWU Fork}"
            export STRAWWU_APT_LABEL="${STRAWWU_FORK_APT_LABEL:-StrawWU Fork APT Repository}"
            export STRAWWU_VERSION="${VERSION}"
            bash "${PUBLISH}" --deb-dir "${DEB_INPUT}"
            ;;
    esac
}

main "$@"
