#!/usr/bin/env bash
# build-appimage.sh — Produce AppImage (or equivalent portable bundle) from
# the self-contained prefix (Portable Core pc2).
# Does not touch ISO / Wine / Proton / WinBox naming.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
PREFIX="${STRAWWU_PREFIX:-${SCRIPT_DIR}/prefix}"
OUT_DIR="${STRAWWU_APPIMAGE_OUT:-${SCRIPT_DIR}/appimage/dist}"
APPDIR_NAME="StrawWU-Core-${VERSION}-x86_64.AppDir"
APPDIR="${OUT_DIR}/${APPDIR_NAME}"
ARCH="x86_64"
ARTIFACT_STEM="StrawWU-Core-${VERSION}-${ARCH}"
PORTABLE_TGZ="${OUT_DIR}/${ARTIFACT_STEM}.portable.tar.gz"
APPIMAGE_PATH="${OUT_DIR}/${ARTIFACT_STEM}.AppImage"
TOOLS_DIR="${SCRIPT_DIR}/appimage/.tools"
SUMS_OUT="${STRAWWU_PORTABLE_SHA256SUMS:-${REPO_ROOT}/tests/portable/output/SHA256SUMS}"
FORCE_BUNDLE_ONLY="${STRAWWU_PORTABLE_BUNDLE_ONLY:-0}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[portable-appimage] $*" >&2; }

command -v python3 >/dev/null 2>&1 || die "python3 required"
command -v tar >/dev/null 2>&1 || die "tar required"

ensure_prefix() {
    if [[ ! -x "${PREFIX}/bin/strawwu" ]]; then
        log "prefix missing — invoking build-prefix.sh"
        STRAWWU_PREFIX="${PREFIX}" bash "${SCRIPT_DIR}/build-prefix.sh" \
            || die "build-prefix.sh failed"
    fi
    [[ -x "${PREFIX}/bin/strawwu" ]] || die "prefix binary missing: ${PREFIX}/bin/strawwu"
}

fetch_appimagetool() {
    local tool="${TOOLS_DIR}/appimagetool-${ARCH}.AppImage"
    local url="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    mkdir -p "${TOOLS_DIR}"
    if [[ ! -x "${tool}" ]]; then
        log "fetching appimagetool → ${tool}"
        curl -fsSL -o "${tool}.partial" "${url}" || return 1
        mv "${tool}.partial" "${tool}"
        chmod 755 "${tool}"
    fi
    # Prefer extracted AppRun (no FUSE required on build host).
    if [[ ! -x "${TOOLS_DIR}/appimagetool.AppDir/AppRun" ]]; then
        (
            cd "${TOOLS_DIR}"
            rm -rf appimagetool.AppDir squashfs-root
            "${tool}" --appimage-extract >/dev/null
            mv squashfs-root appimagetool.AppDir
        ) || return 1
    fi
    echo "${TOOLS_DIR}/appimagetool.AppDir/AppRun"
}

stage_appdir() {
    log "staging AppDir → ${APPDIR}"
    rm -rf "${APPDIR}"
    mkdir -p \
        "${APPDIR}/usr/bin" \
        "${APPDIR}/usr/lib/strawwu" \
        "${APPDIR}/usr/share/strawwu" \
        "${APPDIR}/usr/share/applications" \
        "${APPDIR}/usr/share/icons/hicolor/256x256/apps" \
        "${APPDIR}/usr/share/doc/strawwu-portable" \
        "${APPDIR}/usr/var/lib/strawwu"

    install -m 755 "${PREFIX}/bin/strawwu" "${APPDIR}/usr/bin/strawwu"
    if [[ -x "${PREFIX}/bin/strawwu-env" ]]; then
        install -m 755 "${PREFIX}/bin/strawwu-env" "${APPDIR}/usr/bin/strawwu-env"
    fi

    # Bundled libs: inventory path usr/lib/strawwu + keep $ORIGIN/../lib fallback.
    if [[ -d "${PREFIX}/lib" ]]; then
        find "${PREFIX}/lib" -maxdepth 1 -type f \( -name '*.so' -o -name '*.so.*' \) \
            -exec cp -a {} "${APPDIR}/usr/lib/strawwu/" \;
        # Symlink tree so existing rpath $ORIGIN/../lib still resolves.
        mkdir -p "${APPDIR}/usr/lib"
        if compgen -G "${APPDIR}/usr/lib/strawwu/*" >/dev/null; then
            for so in "${APPDIR}/usr/lib/strawwu/"*; do
                base="$(basename "${so}")"
                ln -sfn "strawwu/${base}" "${APPDIR}/usr/lib/${base}"
            done
        fi
    fi

    if command -v patchelf >/dev/null 2>&1; then
        patchelf --set-rpath '$ORIGIN/../lib/strawwu:$ORIGIN/../lib' \
            "${APPDIR}/usr/bin/strawwu" 2>/dev/null \
            || log "patchelf rpath skipped"
    fi

    if [[ -d "${PREFIX}/share/strawwu" ]]; then
        cp -a "${PREFIX}/share/strawwu/." "${APPDIR}/usr/share/strawwu/"
    fi
    if [[ -d "${PREFIX}/share/doc/strawwu-portable" ]]; then
        cp -a "${PREFIX}/share/doc/strawwu-portable/." \
            "${APPDIR}/usr/share/doc/strawwu-portable/"
    fi
    if [[ -d "${PREFIX}/var/lib/strawwu" ]]; then
        cp -a "${PREFIX}/var/lib/strawwu/." "${APPDIR}/usr/var/lib/strawwu/"
    else
        cat > "${APPDIR}/usr/var/lib/strawwu/app-registry.json" <<'EOF'
{
  "schema_version": "1.0",
  "apps": []
}
EOF
    fi

    # Desktop entry + icon (required by appimagetool).
    local icon_src="${REPO_ROOT}/os-image/config/branding/logo-icon-256.png"
    if [[ ! -f "${icon_src}" ]]; then
        icon_src="${REPO_ROOT}/os-image/config/branding/source/strawwu-logo-icon.png"
    fi
    [[ -f "${icon_src}" ]] || die "missing branding icon for AppImage"
    install -m 644 "${icon_src}" "${APPDIR}/strawwu.png"
    install -m 644 "${icon_src}" \
        "${APPDIR}/usr/share/icons/hicolor/256x256/apps/strawwu.png"

    cat > "${APPDIR}/strawwu.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=StrawWU Core
Comment=StrawWU Portable Win-compat core — click .exe to install & launch
Exec=strawwu
Icon=strawwu
Categories=System;
Terminal=true
EOF
    cp -a "${APPDIR}/strawwu.desktop" "${APPDIR}/usr/share/applications/strawwu.desktop"

    # Prefer packaged open-handler from prefix when present.
    if [[ -f "${PREFIX}/share/applications/strawwu-open.desktop" ]]; then
        install -m 644 "${PREFIX}/share/applications/strawwu-open.desktop" \
            "${APPDIR}/usr/share/applications/strawwu-open.desktop"
    else
        cat > "${APPDIR}/usr/share/applications/strawwu-open.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=StrawWU
Comment=Install or run Windows .exe/.msi with StrawWU Portable Core
Exec=strawwu open %f
TryExec=strawwu
Icon=strawwu
Terminal=false
Categories=System;Utility;
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;application/x-msi;
NoDisplay=false
StartupNotify=true
X-StrawWU-Kind=open-handler
EOF
    fi

    cat > "${APPDIR}/AppRun" <<'EOF'
#!/usr/bin/env bash
# AppRun — StrawWU Portable Core entry (AppImage / AppDir).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STRAWWU_PREFIX="${STRAWWU_PREFIX:-${HERE}/usr}"
export STRAWWU_APP_REGISTRY="${STRAWWU_APP_REGISTRY:-${STRAWWU_PREFIX}/var/lib/strawwu/app-registry.json}"
export PATH="${STRAWWU_PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${STRAWWU_PREFIX}/lib/strawwu:${STRAWWU_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${STRAWWU_PREFIX}/bin/strawwu" "$@"
EOF
    chmod 755 "${APPDIR}/AppRun"

    # Manifest for the AppDir / bundle.
    python3 - "${APPDIR}" "${VERSION}" "${PREFIX}" <<'PY'
import json, os, sys, time
appdir, version, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
libs = []
lib_dir = os.path.join(appdir, "usr", "lib", "strawwu")
if os.path.isdir(lib_dir):
    libs = sorted(
        f for f in os.listdir(lib_dir)
        if f.endswith(".so") or ".so." in f
    )
manifest = {
    "schema": "strawwu-portable-appimage/v1",
    "stage": "pc2-appimage",
    "version": version,
    "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "appdir": appdir,
    "source_prefix": prefix,
    "entry": "AppRun",
    "binary": "usr/bin/strawwu",
    "bundled_libs": libs,
    "notes": [
        "Portable Core AppImage / AppDir bundle; host glibc remains ABI baseline.",
        "Not a full Windows compatibility claim; no Wine/Proton substrate.",
        "No WinBox naming.",
    ],
}
path = os.path.join(appdir, "usr", "share", "strawwu", "portable-appimage.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(path)
PY
}

pack_portable_tgz() {
    log "packing portable tar.gz → ${PORTABLE_TGZ}"
    mkdir -p "${OUT_DIR}"
    rm -f "${PORTABLE_TGZ}"
    tar -C "${OUT_DIR}" -czf "${PORTABLE_TGZ}" "${APPDIR_NAME}"
    [[ -f "${PORTABLE_TGZ}" ]] || die "portable tar.gz missing"
}

build_appimage() {
    if [[ "${FORCE_BUNDLE_ONLY}" == "1" ]]; then
        log "STRAWWU_PORTABLE_BUNDLE_ONLY=1 — skipping real AppImage"
        rm -f "${APPIMAGE_PATH}"
        return 0
    fi
    local tool
    if ! tool="$(fetch_appimagetool)"; then
        log "appimagetool unavailable — equivalent portable.tar.gz only"
        rm -f "${APPIMAGE_PATH}"
        return 0
    fi
    log "building AppImage with ${tool}"
    rm -f "${APPIMAGE_PATH}"
    (
        cd "${OUT_DIR}"
        export ARCH
        # -n: skip AppStream; --no-appstream alias via -n
        if ! ARCH="${ARCH}" "${tool}" -n "${APPDIR_NAME}" "${APPIMAGE_PATH}"; then
            log "appimagetool failed — keeping portable.tar.gz as equivalent bundle"
            rm -f "${APPIMAGE_PATH}"
            return 0
        fi
    )
    if [[ -f "${APPIMAGE_PATH}" ]]; then
        chmod 755 "${APPIMAGE_PATH}"
        log "AppImage ready: ${APPIMAGE_PATH} ($(du -h "${APPIMAGE_PATH}" | awk '{print $1}'))"
    fi
}

write_sha256sums() {
    mkdir -p "$(dirname "${SUMS_OUT}")"
    (
        cd "${OUT_DIR}"
        local files=()
        [[ -f "${PORTABLE_TGZ}" ]] && files+=("$(basename "${PORTABLE_TGZ}")")
        [[ -f "${APPIMAGE_PATH}" ]] && files+=("$(basename "${APPIMAGE_PATH}")")
        [[ ${#files[@]} -gt 0 ]] || die "no artifacts to checksum"
        sha256sum "${files[@]}" > "${SUMS_OUT}"
    )
    # Also keep a copy next to artifacts for redistribution.
    cp -a "${SUMS_OUT}" "${OUT_DIR}/SHA256SUMS"
    log "wrote ${SUMS_OUT}"
    cat "${SUMS_OUT}"
}

self_check() {
    log "self-check AppDir AppRun"
    export STRAWWU_APP_REGISTRY="${APPDIR}/usr/var/lib/strawwu/app-registry.json"
    "${APPDIR}/AppRun" --version || die "AppRun --version failed"
    "${APPDIR}/AppRun" status || die "AppRun status failed"
}

main() {
    log "building StrawWU Core AppImage/bundle ${VERSION}"
    ensure_prefix
    mkdir -p "${OUT_DIR}"
    stage_appdir
    pack_portable_tgz
    build_appimage
    write_sha256sums
    self_check
    log "artifacts in ${OUT_DIR}:"
    ls -lh "${OUT_DIR}" | sed 's/^/[portable-appimage] /'
    log "build-appimage PASS"
}

main "$@"
