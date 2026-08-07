#!/usr/bin/env bash
# build-flatpak.sh — Stage portable prefix + build org.strawwu.Core Flatpak (pc3).
# Does not touch ISO / Wine / Proton / WinBox naming.
# Honest PARTIAL: sandbox cannot fully host PE + SubsystemSession without host FS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
PREFIX="${STRAWWU_PREFIX:-${SCRIPT_DIR}/prefix}"
FLATPAK_DIR="${SCRIPT_DIR}/flatpak"
MANIFEST="${FLATPAK_DIR}/org.strawwu.Core.yaml"
STAGED="${FLATPAK_DIR}/staged"
BUILD_DIR="${STRAWWU_FLATPAK_BUILD:-${FLATPAK_DIR}/.build}"
REPO_DIR="${STRAWWU_FLATPAK_REPO:-${FLATPAK_DIR}/repo}"
STATE_DIR="${STRAWWU_FLATPAK_STATE:-${FLATPAK_DIR}/.flatpak-builder}"
BUNDLE="${STRAWWU_FLATPAK_BUNDLE:-${FLATPAK_DIR}/dist/org.strawwu.Core-${VERSION}.flatpak}"
APP_ID="org.strawwu.Core"
RUNTIME_BRANCH="${STRAWWU_FLATPAK_RUNTIME:-24.08}"
SKIP_INSTALL_RUNTIME="${STRAWWU_FLATPAK_SKIP_RUNTIME:-0}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[portable-flatpak] $*" >&2; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

ensure_prefix() {
    if [[ ! -x "${PREFIX}/bin/strawwu" ]]; then
        log "prefix missing — invoking build-prefix.sh"
        STRAWWU_PREFIX="${PREFIX}" bash "${SCRIPT_DIR}/build-prefix.sh" \
            || die "build-prefix.sh failed"
    fi
    [[ -x "${PREFIX}/bin/strawwu" ]] || die "prefix binary missing: ${PREFIX}/bin/strawwu"
}

ensure_flatpak_tools() {
    command -v flatpak >/dev/null 2>&1 || die "flatpak CLI required (apt install flatpak)"
    command -v flatpak-builder >/dev/null 2>&1 \
        || die "flatpak-builder required (apt install flatpak-builder)"
}

ensure_runtime() {
    if [[ "${SKIP_INSTALL_RUNTIME}" == "1" ]]; then
        log "skipping runtime install (STRAWWU_FLATPAK_SKIP_RUNTIME=1)"
        return 0
    fi
    if ! flatpak info "org.freedesktop.Platform//${RUNTIME_BRANCH}" >/dev/null 2>&1 \
        || ! flatpak info "org.freedesktop.Sdk//${RUNTIME_BRANCH}" >/dev/null 2>&1; then
        log "adding flathub remote (user) if missing"
        flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo \
            || die "failed to add flathub remote"
        log "installing Freedesktop Platform/Sdk ${RUNTIME_BRANCH} (user)"
        flatpak install -y --user "flathub" \
            "org.freedesktop.Platform//${RUNTIME_BRANCH}" \
            "org.freedesktop.Sdk//${RUNTIME_BRANCH}" \
            || die "failed to install Flatpak runtime/sdk"
    else
        log "runtime/sdk ${RUNTIME_BRANCH} already present"
    fi
}

stage_sources() {
    log "staging Flatpak sources → ${STAGED}"
    rm -rf "${STAGED}"
    mkdir -p \
        "${STAGED}/bin" \
        "${STAGED}/lib" \
        "${STAGED}/share/strawwu" \
        "${STAGED}/share/doc/strawwu-portable" \
        "${STAGED}/share/applications" \
        "${STAGED}/share/icons/hicolor/256x256/apps" \
        "${STAGED}/share/metainfo" \
        "${STAGED}/var/lib/strawwu"

    install -m 755 "${PREFIX}/bin/strawwu" "${STAGED}/bin/strawwu"
    if [[ -x "${PREFIX}/bin/strawwu-env" ]]; then
        install -m 755 "${PREFIX}/bin/strawwu-env" "${STAGED}/bin/strawwu-env"
    fi

    if [[ -d "${PREFIX}/lib" ]]; then
        find "${PREFIX}/lib" -maxdepth 1 -type f \( -name '*.so' -o -name '*.so.*' \) \
            -exec cp -a {} "${STAGED}/lib/" \;
    fi

    if [[ -d "${PREFIX}/share/strawwu" ]]; then
        cp -a "${PREFIX}/share/strawwu/." "${STAGED}/share/strawwu/"
    fi
    if [[ -d "${PREFIX}/share/doc/strawwu-portable" ]]; then
        cp -a "${PREFIX}/share/doc/strawwu-portable/." \
            "${STAGED}/share/doc/strawwu-portable/"
    fi
    if [[ -d "${PREFIX}/var/lib/strawwu" ]]; then
        cp -a "${PREFIX}/var/lib/strawwu/." "${STAGED}/var/lib/strawwu/"
    else
        printf '%s\n' '{"schema_version":"1.0","apps":[]}' \
            > "${STAGED}/var/lib/strawwu/app-registry.json"
    fi

    local icon_src="${REPO_ROOT}/os-image/config/branding/logo-icon-256.png"
    if [[ ! -f "${icon_src}" ]]; then
        icon_src="${REPO_ROOT}/os-image/config/branding/source/strawwu-logo-icon.png"
    fi
    [[ -f "${icon_src}" ]] || die "missing branding icon for Flatpak"
    install -m 644 "${icon_src}" \
        "${STAGED}/share/icons/hicolor/256x256/apps/${APP_ID}.png"

    cat > "${STAGED}/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=StrawWU Core
Comment=StrawWU Portable Win-compat core (CLI) — not a full Windows compatibility claim
Exec=strawwu
Icon=${APP_ID}
Categories=System;
Terminal=true
EOF

    cat > "${STAGED}/share/metainfo/${APP_ID}.metainfo.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_ID}</id>
  <name>StrawWU Core</name>
  <summary>Portable Win-compat core (CLI) — Flatpak packaging is PARTIAL</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>LicenseRef-proprietary</project_license>
  <description>
    <p>
      StrawWU Portable Core packages the Win-compat CLI (runtime / nt / launcher /
      graphics·audio bridges). This Flatpak is an honest PARTIAL packaging path:
      PE load and SubsystemSession require host filesystem visibility and are not
      fully sandbox-compatible. This is not a full Windows compatibility claim.
      No Wine or Proton substrate.
    </p>
  </description>
  <launchable type="desktop-id">${APP_ID}.desktop</launchable>
  <releases>
    <release version="${VERSION}" date="$(date -u +%Y-%m-%d)"/>
  </releases>
  <content_rating type="oars-1.1"/>
</component>
EOF

    # Flatpak-specific manifest note inside staged tree.
    python3 - "${STAGED}" "${VERSION}" "${PREFIX}" <<'PY'
import json, os, sys, time
staged, version, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
libs = []
lib_dir = os.path.join(staged, "lib")
if os.path.isdir(lib_dir):
    libs = sorted(f for f in os.listdir(lib_dir) if f.endswith(".so") or ".so." in f)
doc = {
    "schema": "strawwu-portable-flatpak/v1",
    "stage": "pc3-flatpak",
    "version": version,
    "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "app_id": "org.strawwu.Core",
    "source_prefix": prefix,
    "bundled_libs": libs,
    "sandbox_status": "PARTIAL",
    "sandbox_notes": [
        "PE load and SubsystemSession need host filesystem (--filesystem=host).",
        "Default Flatpak isolation alone is insufficient for arbitrary PE paths.",
        "Not a full Windows compatibility claim; powered by Wine when backend=wine; no WinBox naming.",
    ],
}
path = os.path.join(staged, "share", "strawwu", "portable-flatpak.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(path)
PY
}

run_flatpak_builder() {
    [[ -f "${MANIFEST}" ]] || die "missing manifest: ${MANIFEST}"
    mkdir -p "${BUILD_DIR}" "${REPO_DIR}" "$(dirname "${BUNDLE}")"
    log "flatpak-builder → ${BUILD_DIR} (repo ${REPO_DIR})"
    # --force-clean: reproducible stage; --repo: export OSTree repo for bundle.
    flatpak-builder \
        --user \
        --force-clean \
        --install-deps-from=flathub \
        --state-dir="${STATE_DIR}" \
        --repo="${REPO_DIR}" \
        "${BUILD_DIR}" \
        "${MANIFEST}" \
        || die "flatpak-builder failed"

    log "building single-file bundle → ${BUNDLE}"
    rm -f "${BUNDLE}"
    flatpak build-bundle "${REPO_DIR}" "${BUNDLE}" "${APP_ID}" \
        || die "flatpak build-bundle failed"
    [[ -f "${BUNDLE}" ]] || die "bundle missing: ${BUNDLE}"
    log "bundle ready: ${BUNDLE} ($(du -h "${BUNDLE}" | awk '{print $1}'))"
}

install_local_for_smoke() {
    # Install from local OSTree repo into user installation for smoke runs.
    if flatpak info --user "${APP_ID}" >/dev/null 2>&1; then
        flatpak uninstall -y --user "${APP_ID}" >/dev/null 2>&1 || true
    fi
    local remote="strawwu-portable-local"
    local repo_uri="file://${REPO_DIR}"
    if flatpak remotes --user 2>/dev/null | awk '{print $1}' | grep -qx "${remote}"; then
        flatpak remote-modify --user --url="${repo_uri}" --no-gpg-verify "${remote}" \
            >/dev/null 2>&1 || true
    else
        flatpak remote-add --user --if-not-exists --no-gpg-verify \
            "${remote}" "${repo_uri}" \
            || die "failed to add local Flatpak remote"
    fi
    flatpak install -y --user --reinstall "${remote}" "${APP_ID}" \
        || die "failed to install local Flatpak for smoke"
}

self_check() {
    log "self-check flatpak run ${APP_ID}"
    local version_out status_out
    version_out="$(flatpak run "${APP_ID}" --version)" \
        || die "flatpak run --version failed"
    status_out="$(flatpak run "${APP_ID}" status)" \
        || die "flatpak run status failed"
    log "version: ${version_out}"
    log "status:  ${status_out}"
}

write_build_meta() {
    local out="${FLATPAK_DIR}/dist/portable-flatpak-build.json"
    mkdir -p "$(dirname "${out}")"
    python3 - "${out}" "${VERSION}" "${BUNDLE}" "${REPO_DIR}" "${MANIFEST}" <<'PY'
import json, os, sys, time
out, version, bundle, repo, manifest = sys.argv[1:6]
doc = {
    "schema": "strawwu-portable-flatpak-build/v1",
    "stage": "pc3-flatpak",
    "version": version,
    "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "app_id": "org.strawwu.Core",
    "manifest": manifest,
    "bundle": bundle if os.path.isfile(bundle) else None,
    "repo": repo,
    "sandbox_status": "PARTIAL",
    "notes": [
        "CLI --version/status may PASS inside Flatpak.",
        "PE load + SubsystemSession require host filesystem — packaging is PARTIAL.",
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
PY
}

main() {
    log "building StrawWU Core Flatpak ${VERSION}"
    [[ -f "${MANIFEST}" ]] || die "missing ${MANIFEST}"
    ensure_prefix
    ensure_flatpak_tools
    ensure_runtime
    stage_sources
    run_flatpak_builder
    install_local_for_smoke
    self_check
    write_build_meta
    log "artifacts:"
    ls -lh "${FLATPAK_DIR}/dist" | sed 's/^/[portable-flatpak] /'
    log "build-flatpak done (sandbox status PARTIAL by design)"
}

main "$@"
