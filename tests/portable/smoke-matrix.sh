#!/usr/bin/env bash
# smoke-matrix.sh — Portable Core cross-distro container matrix (pc4).
# Installs the portable bundle into ≥3 distro containers and smokes CLI/runtime.
# Writes tests/portable/output/matrix.json (top-level status=PASS|FAIL).
# Forbidden: ISO / physical Live USB campaigns.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORTABLE_ROOT="${REPO_ROOT}/components/packaging/portable"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/matrix.json"
SUMS="${OUT_DIR}/SHA256SUMS"
DIST="${STRAWWU_APPIMAGE_OUT:-${PORTABLE_ROOT}/appimage/dist}"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
BUILD_IF_MISSING=1
DRY_RUN=0
PULL_IMAGES=1

# Default matrix: Ubuntu LTS, Fedora, Arch (deb / rpm / pacman families).
# Override with STRAWWU_PORTABLE_MATRIX_IMAGES="id|image|family ..."
DEFAULT_MATRIX=(
    "ubuntu-24.04|ubuntu:24.04|debian"
    "fedora-41|fedora:41|rpm"
    "archlinux|archlinux:latest|arch"
)

usage() {
    cat <<EOF
Usage: smoke-matrix.sh [--dry-run] [--no-build] [--no-pull] [-h|--help]

Portable Core cross-distro container matrix (pc4).

  --dry-run     Check scripts/layout only; do not require artifacts or containers
  --no-build    Do not invoke build-appimage.sh when portable artifacts missing
  --no-pull     Do not docker pull images (use local cache only)
  -h, --help    Show this help

PASS (pc4): ≥3 distro containers install portable artifact and smoke
            AppRun --version / status; ${OUT_JSON} top-level status=PASS.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --no-build) BUILD_IF_MISSING=0; shift ;;
        --no-pull) PULL_IMAGES=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "ERROR: unknown arg: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-matrix] $*"; }

write_matrix_json() {
    local status="$1"
    local results_json="$2"
    mkdir -p "${OUT_DIR}"
    python3 - "${OUT_JSON}" "${status}" "${VERSION}" "${DIST}" "${results_json}" <<'PY'
import json, sys, time
out, status, version, dist, results_raw = sys.argv[1:6]
results = json.loads(results_raw)
distros = []
for r in results:
    distros.append({
        "id": r.get("id"),
        "image": r.get("image"),
        "family": r.get("family"),
        "status": r.get("status"),
    })
doc = {
    "schema": "strawwu-portable-cross-distro-matrix/v1",
    "stage": "pc4-cross-distro-smoke",
    "status": status,
    "version": version,
    "dist": dist,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "distros": distros,
    "results": results,
    "summary": {
        "total": len(results),
        "pass": sum(1 for r in results if r.get("status") == "PASS"),
        "fail": sum(1 for r in results if r.get("status") == "FAIL"),
        "skip": sum(1 for r in results if r.get("status") == "SKIP"),
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no physical Live USB / ISO hardware campaign",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
}

fail_matrix() {
    local msg="$1"
    local results_json="${2:-[]}"
    write_matrix_json "FAIL" "${results_json}" >/dev/null || true
    die "${msg}"
}

[[ -f "${REPO_ROOT}/docs/plans/portable-core/A3-cross-distro-core.md" ]] \
    || fail_matrix "missing A3 plan"
[[ -d "${PORTABLE_ROOT}/appimage" ]] || fail_matrix "missing portable/appimage/"
[[ -x "${PORTABLE_ROOT}/build-appimage.sh" ]] || fail_matrix "missing build-appimage.sh"
[[ -x "${REPO_ROOT}/tests/portable/smoke-appimage.sh" ]] \
    || fail_matrix "missing smoke-appimage.sh (pc2 prerequisite)"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run PASS (scripts + layout); default matrix entries=${#DEFAULT_MATRIX[@]}"
    exit 0
fi

# Ensure portable artifacts exist (reuse pc2 builder).
need_build=0
if [[ ! -d "${DIST}" ]] || ! compgen -G "${DIST}/StrawWU-Core-*-x86_64.portable.tar.gz" >/dev/null; then
    if [[ ! -d "${DIST}" ]] || ! compgen -G "${DIST}/StrawWU-Core-*-x86_64.AppDir/AppRun" >/dev/null; then
        need_build=1
    fi
fi

if [[ "${need_build}" -eq 1 ]]; then
    if [[ "${BUILD_IF_MISSING}" -eq 1 ]]; then
        log "artifacts missing — invoking build-appimage.sh"
        STRAWWU_APPIMAGE_OUT="${DIST}" \
            STRAWWU_PORTABLE_SHA256SUMS="${SUMS}" \
            bash "${PORTABLE_ROOT}/build-appimage.sh" \
            || fail_matrix "build-appimage.sh failed"
    else
        fail_matrix "artifacts missing under ${DIST} (use without --no-build)"
    fi
fi

PORTABLE_TGZ="$(compgen -G "${DIST}/StrawWU-Core-*-x86_64.portable.tar.gz" | head -n1 || true)"
APPDIR="$(compgen -G "${DIST}/StrawWU-Core-*-x86_64.AppDir" | head -n1 || true)"

SMOKE_SRC=""
SMOKE_KIND=""
if [[ -n "${PORTABLE_TGZ}" && -f "${PORTABLE_TGZ}" ]]; then
    SMOKE_SRC="$(readlink -f "${PORTABLE_TGZ}")"
    SMOKE_KIND="portable.tar.gz"
elif [[ -n "${APPDIR}" && -x "${APPDIR}/AppRun" ]]; then
    SMOKE_SRC="$(readlink -f "${APPDIR}")"
    SMOKE_KIND="AppDir"
else
    fail_matrix "no portable.tar.gz / AppDir found in ${DIST}"
fi

command -v docker >/dev/null 2>&1 || fail_matrix "docker required for cross-distro matrix"

# Resolve matrix entries.
MATRIX_ENTRIES=()
if [[ -n "${STRAWWU_PORTABLE_MATRIX_IMAGES:-}" ]]; then
    # shellcheck disable=SC2206
    MATRIX_ENTRIES=(${STRAWWU_PORTABLE_MATRIX_IMAGES})
else
    MATRIX_ENTRIES=("${DEFAULT_MATRIX[@]}")
fi

[[ "${#MATRIX_ENTRIES[@]}" -ge 3 ]] \
    || fail_matrix "matrix must define ≥3 distros (got ${#MATRIX_ENTRIES[@]})"

log "artifact=${SMOKE_KIND} path=${SMOKE_SRC}"
log "matrix entries=${#MATRIX_ENTRIES[@]}"

RESULTS_TMP="$(mktemp)"
echo '[]' >"${RESULTS_TMP}"
cleanup() { rm -f "${RESULTS_TMP}"; }
trap cleanup EXIT

append_result() {
    local id="$1" image="$2" family="$3" status="$4" version_out="$5" status_out="$6" detail="$7"
    python3 - "${RESULTS_TMP}" "${id}" "${image}" "${family}" "${status}" \
        "${version_out}" "${status_out}" "${detail}" "${SMOKE_KIND}" <<'PY'
import json, sys, time
path, distro_id, image, family, status, version_out, status_out, detail, kind = sys.argv[1:10]
rows = json.load(open(path, encoding="utf-8"))
rows.append({
    "id": distro_id,
    "image": image,
    "family": family,
    "status": status,
    "artifact_kind": kind,
    "version_output": version_out,
    "status_output": status_out,
    "detail": detail,
    "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
})
with open(path, "w", encoding="utf-8") as fh:
    json.dump(rows, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
}

run_one_distro() {
    local id="$1" image="$2" family="$3"
    local container_out pull_rc run_rc version_out status_out detail

    log "distro=${id} image=${image} family=${family}"

    if [[ "${PULL_IMAGES}" -eq 1 ]]; then
        if ! docker pull "${image}" >/dev/null 2>&1; then
            append_result "${id}" "${image}" "${family}" "FAIL" "" "" "docker pull failed"
            return 1
        fi
    else
        if ! docker image inspect "${image}" >/dev/null 2>&1; then
            append_result "${id}" "${image}" "${family}" "FAIL" "" "" "image not present locally (--no-pull)"
            return 1
        fi
    fi

    container_out="$(mktemp)"
    run_rc=0
    if [[ "${SMOKE_KIND}" == "portable.tar.gz" ]]; then
        docker run --rm \
            -v "${SMOKE_SRC}:/bundle/portable.tar.gz:ro" \
            "${image}" \
            bash -c '
                set -euo pipefail
                # Refuse accidental host strawwu packages if package managers exist.
                if command -v dpkg-query >/dev/null 2>&1; then
                    if dpkg-query -W -f="\${Package}\n" "strawwu-*" 2>/dev/null | grep -q .; then
                        echo "UNEXPECTED: strawwu debs in clean image" >&2
                        exit 1
                    fi
                fi
                if command -v rpm >/dev/null 2>&1; then
                    if rpm -qa "strawwu-*" 2>/dev/null | grep -q .; then
                        echo "UNEXPECTED: strawwu rpms in clean image" >&2
                        exit 1
                    fi
                fi
                if command -v pacman >/dev/null 2>&1; then
                    if pacman -Qq 2>/dev/null | grep -E "^strawwu" >/dev/null; then
                        echo "UNEXPECTED: strawwu pkgs in clean image" >&2
                        exit 1
                    fi
                fi
                mkdir -p /smoke && tar -xzf /bundle/portable.tar.gz -C /smoke
                APPDIR="$(find /smoke -maxdepth 1 -type d -name "*.AppDir" | head -n1)"
                test -n "${APPDIR}"
                test -x "${APPDIR}/AppRun"
                VERSION_OUT="$("${APPDIR}/AppRun" --version)"
                STATUS_OUT="$("${APPDIR}/AppRun" status)"
                printf "VERSION=%s\n" "${VERSION_OUT}"
                printf "STATUS=%s\n" "${STATUS_OUT}"
                printf "APPDIR=%s\n" "${APPDIR}"
            ' >"${container_out}" 2>&1 || run_rc=$?
    else
        docker run --rm \
            -v "${SMOKE_SRC}:/smoke/AppDir:ro" \
            "${image}" \
            bash -c '
                set -euo pipefail
                test -x /smoke/AppDir/AppRun
                VERSION_OUT="$(/smoke/AppDir/AppRun --version)"
                STATUS_OUT="$(/smoke/AppDir/AppRun status)"
                printf "VERSION=%s\n" "${VERSION_OUT}"
                printf "STATUS=%s\n" "${STATUS_OUT}"
                printf "APPDIR=/smoke/AppDir\n"
            ' >"${container_out}" 2>&1 || run_rc=$?
    fi

    if [[ "${run_rc}" -ne 0 ]]; then
        detail="$(tail -c 500 "${container_out}" | tr '\n' ' ')"
        append_result "${id}" "${image}" "${family}" "FAIL" "" "" "container smoke failed: ${detail}"
        rm -f "${container_out}"
        return 1
    fi

    version_out="$(grep '^VERSION=' "${container_out}" | sed 's/^VERSION=//' || true)"
    status_out="$(grep '^STATUS=' "${container_out}" | sed 's/^STATUS=//' || true)"
    rm -f "${container_out}"

    if [[ -z "${version_out}" || -z "${status_out}" ]]; then
        append_result "${id}" "${image}" "${family}" "FAIL" "${version_out}" "${status_out}" \
            "missing VERSION/STATUS output"
        return 1
    fi

    log "  version: ${version_out}"
    log "  status:  ${status_out}"
    append_result "${id}" "${image}" "${family}" "PASS" "${version_out}" "${status_out}" "ok"
    return 0
}

overall_fail=0
for entry in "${MATRIX_ENTRIES[@]}"; do
    IFS='|' read -r distro_id distro_image distro_family <<<"${entry}"
    [[ -n "${distro_id}" && -n "${distro_image}" && -n "${distro_family}" ]] \
        || fail_matrix "invalid matrix entry: ${entry}" "$(cat "${RESULTS_TMP}")"
    if ! run_one_distro "${distro_id}" "${distro_image}" "${distro_family}"; then
        overall_fail=1
    fi
done

RESULTS_JSON="$(cat "${RESULTS_TMP}")"
PASS_COUNT="$(python3 -c 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r.get("status")=="PASS"))' <<<"${RESULTS_JSON}")"
TOTAL_COUNT="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' <<<"${RESULTS_JSON}")"

if [[ "${PASS_COUNT}" -lt 3 || "${overall_fail}" -ne 0 || "${PASS_COUNT}" -ne "${TOTAL_COUNT}" ]]; then
    write_matrix_json "FAIL" "${RESULTS_JSON}" >/dev/null
    die "matrix FAIL: pass=${PASS_COUNT}/${TOTAL_COUNT} (need all PASS and ≥3)"
fi

write_matrix_json "PASS" "${RESULTS_JSON}" >/dev/null
log "wrote ${OUT_JSON}"
log "cross-distro matrix PASS (${PASS_COUNT}/${TOTAL_COUNT})"
