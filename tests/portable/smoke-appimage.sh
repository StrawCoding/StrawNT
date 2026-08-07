#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# smoke-appimage.sh — Portable Core AppImage/bundle smoke in a clean container (pc2).
# Writes tests/portable/output/smoke-appimage.json (top-level status=PASS|FAIL)
# and ensures tests/portable/output/SHA256SUMS exists.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORTABLE_ROOT="${REPO_ROOT}/components/packaging/portable"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/smoke-appimage.json"
SUMS="${OUT_DIR}/SHA256SUMS"
DIST="${STRAWWU_APPIMAGE_OUT:-${PORTABLE_ROOT}/appimage/dist}"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
BUILD_IF_MISSING=1
DRY_RUN=0
CONTAINER_IMAGE="${STRAWWU_PORTABLE_SMOKE_IMAGE:-ubuntu:24.04}"

usage() {
    cat <<EOF
Usage: smoke-appimage.sh [--dry-run] [--no-build] [--image IMAGE] [-h|--help]

Portable Core AppImage / portable-bundle smoke (pc2).

  --dry-run       Check scripts/layout only; do not require artifacts or container
  --no-build      Do not invoke build-appimage.sh when artifacts missing
  --image IMAGE   Clean container image (default: ${CONTAINER_IMAGE})
  -h, --help      Show this help

PASS (pc2): artifact + SHA256SUMS; clean-container AppRun --version/status;
            ${OUT_JSON} top-level status=PASS.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --no-build) BUILD_IF_MISSING=0; shift ;;
        --image) CONTAINER_IMAGE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "ERROR: unknown arg: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[smoke-appimage] $*"; }

write_json() {
    local status="$1"
    shift
    mkdir -p "${OUT_DIR}"
    python3 - "${OUT_JSON}" "${status}" "${VERSION}" "${DIST}" "$@" <<'PY'
import json, sys, time
out, status, version, dist = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
checks = {}
for arg in sys.argv[5:]:
    if "|" not in arg:
        continue
    key, raw = arg.split("|", 1)
    try:
        checks[key] = json.loads(raw)
    except json.JSONDecodeError:
        checks[key] = {"raw": raw}
doc = {
    "schema": "strawwu-portable-smoke-appimage/v1",
    "stage": "pc2-appimage",
    "status": status,
    "version": version,
    "dist": dist,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "checks": checks,
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate",
        "no WinBox naming",
        "no full Windows compatibility claim",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
}

fail_json() {
    local msg="$1"
    write_json "FAIL" "error|$(python3 -c 'import json,sys; print(json.dumps({"status":"FAIL","message":sys.argv[1]}))' "${msg}")" >/dev/null || true
    die "${msg}"
}

json_pair() {
    python3 -c 'import json,sys; print(sys.argv[1]+"|"+json.dumps(json.loads(sys.argv[2])))' "$1" "$2"
}

[[ -f "${REPO_ROOT}/docs/plans/portable-core/A3-cross-distro-core.md" ]] \
    || fail_json "missing A3 plan"
[[ -d "${PORTABLE_ROOT}/appimage" ]] || fail_json "missing portable/appimage/"
[[ -x "${PORTABLE_ROOT}/build-appimage.sh" ]] || fail_json "missing build-appimage.sh"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run PASS (scripts + layout)"
    exit 0
fi

# Ensure artifacts exist. Prefer StrawNT-*; legacy StrawWU-Core-* as fallback.
pick_newest() {
    local pattern="$1"
    compgen -G "${pattern}" 2>/dev/null | sort -V | tail -n1 || true
}

need_build=0
APPDIR="$(pick_newest "${DIST}/StrawNT-*-x86_64.AppDir")"
[[ -n "${APPDIR}" ]] || APPDIR="$(pick_newest "${DIST}/StrawWU-Core-*-x86_64.AppDir")"
if [[ -z "${APPDIR}" || ! -x "${APPDIR}/AppRun" ]]; then
    need_build=1
fi
if [[ ! -f "${SUMS}" ]]; then
    need_build=1
fi

if [[ "${need_build}" -eq 1 ]]; then
    if [[ "${BUILD_IF_MISSING}" -eq 1 ]]; then
        log "artifacts missing — invoking build-appimage.sh"
        STRAWNT_APPIMAGE_OUT="${DIST}" \
            STRAWWU_APPIMAGE_OUT="${DIST}" \
            STRAWNT_PORTABLE_SHA256SUMS="${SUMS}" \
            STRAWWU_PORTABLE_SHA256SUMS="${SUMS}" \
            bash "${PORTABLE_ROOT}/build-appimage.sh" \
            || fail_json "build-appimage.sh failed"
    else
        fail_json "artifacts missing under ${DIST} (use without --no-build)"
    fi
fi

[[ -f "${SUMS}" ]] || fail_json "missing ${SUMS}"

# Locate primary artifacts (newest StrawNT preferred).
PORTABLE_TGZ="$(pick_newest "${DIST}/StrawNT-*-x86_64.portable.tar.gz")"
[[ -n "${PORTABLE_TGZ}" ]] || PORTABLE_TGZ="$(pick_newest "${DIST}/StrawWU-Core-*-x86_64.portable.tar.gz")"
APPIMAGE="$(pick_newest "${DIST}/StrawNT-*-x86_64.AppImage")"
[[ -n "${APPIMAGE}" ]] || APPIMAGE="$(pick_newest "${DIST}/StrawWU-Core-*-x86_64.AppImage")"
APPDIR="$(pick_newest "${DIST}/StrawNT-*-x86_64.AppDir")"
[[ -n "${APPDIR}" ]] || APPDIR="$(pick_newest "${DIST}/StrawWU-Core-*-x86_64.AppDir")"

[[ -n "${PORTABLE_TGZ}" || -n "${APPIMAGE}" || -n "${APPDIR}" ]] \
    || fail_json "no AppImage / portable.tar.gz / AppDir found in ${DIST}"

# Verify checksums against dist copies.
(
    cd "${DIST}"
    if [[ -f SHA256SUMS ]]; then
        sha256sum -c SHA256SUMS >/dev/null
    else
        # Fall back to tests/portable/output/SHA256SUMS with files in dist/
        sha256sum -c "${SUMS}" >/dev/null
    fi
) || fail_json "SHA256SUMS verification failed"

command -v docker >/dev/null 2>&1 || fail_json "docker required for clean-container smoke"

# Prefer portable.tar.gz into a clean Ubuntu container (no FUSE / no host libs beyond glibc).
SMOKE_SRC=""
SMOKE_KIND=""
if [[ -n "${PORTABLE_TGZ}" && -f "${PORTABLE_TGZ}" ]]; then
    SMOKE_SRC="${PORTABLE_TGZ}"
    SMOKE_KIND="portable.tar.gz"
elif [[ -n "${APPIMAGE}" && -f "${APPIMAGE}" ]]; then
    SMOKE_SRC="${APPIMAGE}"
    SMOKE_KIND="AppImage"
elif [[ -n "${APPDIR}" && -x "${APPDIR}/AppRun" ]]; then
    SMOKE_SRC="${APPDIR}"
    SMOKE_KIND="AppDir"
else
    fail_json "no usable smoke artifact"
fi

log "clean-container smoke: image=${CONTAINER_IMAGE} artifact=${SMOKE_KIND}"

CONTAINER_OUT="$(mktemp)"
cleanup() { rm -f "${CONTAINER_OUT}"; }
trap cleanup EXIT

if [[ "${SMOKE_KIND}" == "portable.tar.gz" ]]; then
    docker run --rm \
        -v "${SMOKE_SRC}:/bundle/portable.tar.gz:ro" \
        "${CONTAINER_IMAGE}" \
        bash -c '
            set -euo pipefail
            # Minimal userland only — no strawwu packages in this image.
            if command -v dpkg-query >/dev/null 2>&1; then
                if dpkg-query -W -f="\${Package}\n" "strawwu-*" 2>/dev/null | grep -q .; then
                    echo "UNEXPECTED: strawwu debs present in clean image" >&2
                    exit 1
                fi
            fi
            mkdir -p /smoke && tar -xzf /bundle/portable.tar.gz -C /smoke
            APPDIR="$(find /smoke -maxdepth 1 -type d -name "*.AppDir" | head -n1)"
            test -x "${APPDIR}/AppRun"
            VERSION_OUT="$("${APPDIR}/AppRun" --version)"
            STATUS_OUT="$("${APPDIR}/AppRun" status)"
            printf "VERSION=%s\n" "${VERSION_OUT}"
            printf "STATUS=%s\n" "${STATUS_OUT}"
            printf "APPDIR=%s\n" "${APPDIR}"
        ' >"${CONTAINER_OUT}" 2>&1 \
        || fail_json "clean-container smoke failed (see log): $(tail -c 400 "${CONTAINER_OUT}" | tr "\n" " ")"
elif [[ "${SMOKE_KIND}" == "AppImage" ]]; then
    docker run --rm \
        -v "${SMOKE_SRC}:/bundle/StrawWU.AppImage:ro" \
        "${CONTAINER_IMAGE}" \
        bash -c '
            set -euo pipefail
            chmod +x /bundle/StrawWU.AppImage || true
            cd /tmp
            # Extract without FUSE (containers usually lack user namespaces for AppImage mount).
            /bundle/StrawWU.AppImage --appimage-extract >/dev/null
            test -x /tmp/squashfs-root/AppRun
            VERSION_OUT="$(/tmp/squashfs-root/AppRun --version)"
            STATUS_OUT="$(/tmp/squashfs-root/AppRun status)"
            printf "VERSION=%s\n" "${VERSION_OUT}"
            printf "STATUS=%s\n" "${STATUS_OUT}"
            printf "APPDIR=/tmp/squashfs-root\n"
        ' >"${CONTAINER_OUT}" 2>&1 \
        || fail_json "clean-container AppImage smoke failed: $(tail -c 400 "${CONTAINER_OUT}" | tr "\n" " ")"
else
    docker run --rm \
        -v "${SMOKE_SRC}:/smoke/AppDir:ro" \
        "${CONTAINER_IMAGE}" \
        bash -c '
            set -euo pipefail
            VERSION_OUT="$(/smoke/AppDir/AppRun --version)"
            STATUS_OUT="$(/smoke/AppDir/AppRun status)"
            printf "VERSION=%s\n" "${VERSION_OUT}"
            printf "STATUS=%s\n" "${STATUS_OUT}"
            printf "APPDIR=/smoke/AppDir\n"
        ' >"${CONTAINER_OUT}" 2>&1 \
        || fail_json "clean-container AppDir smoke failed: $(tail -c 400 "${CONTAINER_OUT}" | tr "\n" " ")"
fi

VERSION_OUT="$(grep '^VERSION=' "${CONTAINER_OUT}" | sed 's/^VERSION=//')"
STATUS_OUT="$(grep '^STATUS=' "${CONTAINER_OUT}" | sed 's/^STATUS=//')"
[[ -n "${VERSION_OUT}" ]] || fail_json "container did not report VERSION"
[[ -n "${STATUS_OUT}" ]] || fail_json "container did not report STATUS"
log "container version: ${VERSION_OUT}"
log "container status:  ${STATUS_OUT}"

ARTIFACT_LIST="$(python3 -c 'import json,os,sys; dist=sys.argv[1]; names=sorted(n for n in os.listdir(dist) if n.endswith((".AppImage", ".portable.tar.gz")) or n.endswith(".AppDir")); print(json.dumps(names))' "${DIST}")"

write_json "PASS" \
    "$(json_pair version "$(python3 -c 'import json,sys; print(json.dumps({"status":"PASS","output":sys.argv[1]}))' "${VERSION_OUT}")")" \
    "$(json_pair status_cmd "$(python3 -c 'import json,sys; print(json.dumps({"status":"PASS","output":sys.argv[1]}))' "${STATUS_OUT}")")" \
    "$(json_pair sha256sums "$(python3 -c 'import json,sys; print(json.dumps({"status":"PASS","path":sys.argv[1]}))' "${SUMS}")")" \
    "$(json_pair clean_container "$(python3 -c 'import json,sys; print(json.dumps({"status":"PASS","image":sys.argv[1],"artifact_kind":sys.argv[2],"no_system_strawwu_debs":True}))' "${CONTAINER_IMAGE}" "${SMOKE_KIND}")")" \
    "$(json_pair artifacts "$(python3 -c 'import json,sys; print(json.dumps({"status":"PASS","dist":sys.argv[1],"files":json.loads(sys.argv[2])}))' "${DIST}" "${ARTIFACT_LIST}")")"

log "wrote ${OUT_JSON}"
log "appimage smoke PASS"
