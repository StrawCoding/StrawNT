#!/usr/bin/env bash
# bump-version.sh — bump VERSION (a.b.c.d) and sync derived manifests.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
MODE="${1:-iterate}"

read_version() {
    tr -d '[:space:]' < "${VERSION_FILE}"
}

write_version() {
    printf '%s\n' "$1" > "${VERSION_FILE}"
}

parse_version() {
    local v="$1"
    if [[ ! "${v}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "ERROR: invalid VERSION '${v}' (expected a.b.c.d)" >&2
        exit 1
    fi
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    PREVIEW="${BASH_REMATCH[4]}"
}

bump() {
    local current="$1"
    parse_version "${current}"

    case "${MODE}" in
        iterate|preview)
            if [[ "${PREVIEW}" == "0" ]]; then
                PREVIEW=1
            else
                PREVIEW=$((PREVIEW + 1))
            fi
            ;;
        patch|release)
            PATCH=$((PATCH + 1))
            PREVIEW=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            PREVIEW=0
            ;;
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            PREVIEW=0
            ;;
        *)
            echo "Usage: $0 [iterate|preview|patch|release|minor|major]" >&2
            exit 1
            ;;
    esac

    echo "${MAJOR}.${MINOR}.${PATCH}.${PREVIEW}"
}

sync_manifests() {
    local v="$1"
    parse_version "${v}"

    local cargo_version="${MAJOR}.${MINOR}.${PATCH}"
    if [[ "${PREVIEW}" != "0" ]]; then
        cargo_version="${cargo_version}-preview.${PREVIEW}"
    fi

    if [[ -f "${REPO_ROOT}/hub/package.json" ]]; then
        sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"${v}\"/" "${REPO_ROOT}/hub/package.json"
    fi

    if [[ -f "${REPO_ROOT}/components/Cargo.toml" ]]; then
        sed -i "s/^version = \".*\"/version = \"${cargo_version}\"/" "${REPO_ROOT}/components/Cargo.toml"
    fi
}

main() {
    [[ -f "${VERSION_FILE}" ]] || { echo "ERROR: missing ${VERSION_FILE}" >&2; exit 1; }

    local old new
    old="$(read_version)"
    new="$(bump "${old}")"
    write_version "${new}"
    sync_manifests "${new}"

    echo "VERSION: ${old} → ${new} (${MODE})"
}

main "$@"
