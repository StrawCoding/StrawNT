#!/usr/bin/env bash
# build-prefix.sh — Produce a self-contained $STRAWNT_PREFIX for StrawNT (pc1).
# Does not install or depend on system deb packages. STRAWWU_* env accepted as compat.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
COMPONENTS_DIR="${REPO_ROOT}/components"
VERSION="${STRAWNT_VERSION:-${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}}"
PREFIX="${STRAWNT_PREFIX:-${STRAWWU_PREFIX:-${SCRIPT_DIR}/prefix}}"
WITH_HUB="${STRAWNT_PORTABLE_WITH_HUB:-${STRAWWU_PORTABLE_WITH_HUB:-0}}"
BUNDLE_HOST_LIBS="${STRAWNT_PORTABLE_BUNDLE_LIBS:-${STRAWWU_PORTABLE_BUNDLE_LIBS:-1}}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[portable-prefix] $*"; }

command -v cargo >/dev/null 2>&1 || die "cargo not found — install Rust toolchain"
command -v python3 >/dev/null 2>&1 || die "python3 required"

log "building strawnt ${VERSION} → ${PREFIX}"

mkdir -p "${PREFIX}/bin" "${PREFIX}/lib" "${PREFIX}/share/strawnt" \
    "${PREFIX}/share/applications" "${PREFIX}/share/mime/packages" \
    "${PREFIX}/share/doc/strawnt" "${PREFIX}/var/lib/strawnt"

# Link with $ORIGIN/../lib rpath so bundled .so resolve relative to the binary.
export CARGO_TARGET_DIR="${COMPONENTS_DIR}/target"
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-rpath,\$ORIGIN/../lib"

cd "${COMPONENTS_DIR}"
cargo build --release --bin strawnt --bin strawwu

BINARY="${COMPONENTS_DIR}/target/release/strawnt"
[[ -x "${BINARY}" ]] || die "strawnt binary missing at ${BINARY}"

install -m 755 "${BINARY}" "${PREFIX}/bin/strawnt"
# Compat alias (deprecated)
install -m 755 "${COMPONENTS_DIR}/target/release/strawwu" "${PREFIX}/bin/strawwu" 2>/dev/null \
    || ln -sfn strawnt "${PREFIX}/bin/strawwu"
# Keep a non-stripped copy for debugging only when STRAWNT_PORTABLE_KEEP_DEBUG=1
if [[ "${STRAWNT_PORTABLE_KEEP_DEBUG:-${STRAWWU_PORTABLE_KEEP_DEBUG:-0}}" != "1" ]]; then
    strip "${PREFIX}/bin/strawnt" 2>/dev/null || true
    strip "${PREFIX}/bin/strawwu" 2>/dev/null || true
fi

# Bundle non-base host shared libraries (Vulkan/Pulse/etc. if linked).
# Always leave glibc / libgcc / loader to the host — those are ABI baseline.
if [[ "${BUNDLE_HOST_LIBS}" == "1" ]]; then
    mapfile -t NEEDED < <(ldd "${PREFIX}/bin/strawnt" 2>/dev/null | awk '
        /=>/ {
            path=$3
            if (path == "" || path == "not") next
            if (path ~ /ld-linux/) next
            n=path
            sub(".*/", "", n)
            if (n ~ /^(libc|libm|libdl|libpthread|librt|libgcc_s)\.so/) next
            print path
        }
    ')
    for so in "${NEEDED[@]:-}"; do
        [[ -n "${so}" && -f "${so}" ]] || continue
        base="$(basename "${so}")"
        if [[ ! -f "${PREFIX}/lib/${base}" ]]; then
            cp -aL "${so}" "${PREFIX}/lib/${base}"
            chmod 755 "${PREFIX}/lib/${base}" || true
            log "bundled lib/${base}"
        fi
    done
fi

# Optional patchelf reinforcement (rpath already set at link time).
if command -v patchelf >/dev/null 2>&1; then
    patchelf --set-rpath '$ORIGIN/../lib' "${PREFIX}/bin/strawnt" 2>/dev/null \
        || log "patchelf rpath skipped (binary may already embed \$ORIGIN)"
fi

# Optional wincompat baseline assets (if present in tree) + empty local registry.
if [[ -d "${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat" ]]; then
    mkdir -p "${PREFIX}/share/strawnt/wincompat"
    cp -a "${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/." \
        "${PREFIX}/share/strawnt/wincompat/"
fi

cat > "${PREFIX}/var/lib/strawnt/app-registry.json" <<'EOF'
{
  "schema_version": "1.0",
  "apps": []
}
EOF
# Compat path for older STRAWWU_APP_REGISTRY consumers.
mkdir -p "${PREFIX}/var/lib/strawwu"
cp -a "${PREFIX}/var/lib/strawnt/app-registry.json" "${PREFIX}/var/lib/strawwu/app-registry.json"

# Manifest describing what this prefix contains.
python3 - "${PREFIX}" "${VERSION}" "${WITH_HUB}" <<'PY'
import json, os, sys, time
prefix, version, with_hub = sys.argv[1], sys.argv[2], sys.argv[3]
libs = sorted(
    f for f in os.listdir(os.path.join(prefix, "lib"))
    if f.endswith(".so") or ".so." in f
) if os.path.isdir(os.path.join(prefix, "lib")) else []
manifest = {
    "schema": "strawnt-prefix/v1",
    "product": "StrawNT",
    "stage": "pc1-self-contained-prefix",
    "version": version,
    "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "prefix": prefix,
    "components": {
        "runtime": "linked-into:strawnt",
        "nt": "linked-into:strawnt",
        "launcher": "bin/strawnt",
        "cli": "linked-into:strawnt",
        "graphics": "linked-into:strawnt",
        "audio": "workspace-crate (static path via runtime when linked)",
        "hub": "bundled" if with_hub == "1" else "optional-skipped",
    },
    "binary": "bin/strawnt",
    "compat_binary": "bin/strawwu",
    "bundled_libs": libs,
    "notes": [
        "Self-contained StrawNT CLI prefix; primary command is strawnt.",
        "Host glibc / libgcc remain the ABI baseline.",
        "Default execution_backend=native; not a full Windows OS claim; anti-cheat may fail.",
        "Independent product — not an OS/ISO/desktop distribution.",
    ],
}
path = os.path.join(prefix, "share", "strawnt", "portable-prefix.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(path)
PY

# Optional Hub (Electron) — copy sources/notes only unless a built artifact exists.
if [[ "${WITH_HUB}" == "1" ]]; then
    mkdir -p "${PREFIX}/opt/strawnt-hub"
    if [[ -d "${REPO_ROOT}/hub/dist" ]]; then
        cp -a "${REPO_ROOT}/hub/dist/." "${PREFIX}/opt/strawnt-hub/"
        log "bundled hub/dist → opt/strawnt-hub"
    else
        cp -a "${REPO_ROOT}/hub/package.json" "${PREFIX}/opt/strawnt-hub/"
        printf '%s\n' \
            "Hub sources live in repo hub/; build Electron artifact separately for full UI." \
            > "${PREFIX}/opt/strawnt-hub/README.portable.txt"
        log "hub marker installed (no dist/ — optional)"
    fi
fi

cat > "${PREFIX}/share/doc/strawnt/README.txt" <<EOF
StrawNT prefix ${VERSION}

Layout:
  bin/strawnt              CLI entry (primary)
  bin/strawwu              Compat alias (deprecated)
  lib/                     Bundled non-baseline shared objects + \$ORIGIN rpath
  share/strawnt/           Baseline + portable-prefix.json
  share/applications/      Click-to-open handler template (strawnt-open.desktop)
  var/lib/strawnt/         Local app-registry (no system /var/lib required)

Usage:
  export STRAWNT_PREFIX=${PREFIX}
  export STRAWNT_APP_REGISTRY=\$STRAWNT_PREFIX/var/lib/strawnt/app-registry.json
  \$STRAWNT_PREFIX/bin/strawnt --version
  \$STRAWNT_PREFIX/bin/strawnt status
  \$STRAWNT_PREFIX/bin/strawnt integrate
  \$STRAWNT_PREFIX/bin/strawnt open setup.exe

Click-to-open:
  After \`strawnt integrate\`, double-click .exe/.msi in the file manager.
  Apps also get ~/.local/share/applications/<app>.desktop for one-click relaunch.

Independent product — not an OS/ISO/desktop distribution.
EOF

# Template desktop handler (install.sh / \`strawnt integrate\` writes the live copy).
cat > "${PREFIX}/share/applications/strawnt-open.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=StrawNT
GenericName=Windows App Launcher
Comment=Install or run Windows .exe/.msi with StrawNT native PE
Exec=strawnt open %f
TryExec=strawnt
Icon=strawnt
Terminal=false
Categories=System;Utility;
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;application/x-msi;application/x-ms-shortcut;
NoDisplay=false
StartupNotify=true
X-StrawNT-Kind=open-handler
EOF

# Wrapper that sets local registry when invoked from prefix.
cat > "${PREFIX}/bin/strawnt-env" <<EOF
#!/usr/bin/env bash
# Activate StrawNT prefix environment (source or exec helper).
PREFIX="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export STRAWNT_PREFIX="\${PREFIX}"
export STRAWWU_PREFIX="\${STRAWWU_PREFIX:-\${PREFIX}}"
export STRAWNT_APP_REGISTRY="\${STRAWNT_APP_REGISTRY:-\${STRAWWU_APP_REGISTRY:-\${PREFIX}/var/lib/strawnt/app-registry.json}}"
export STRAWWU_APP_REGISTRY="\${STRAWWU_APP_REGISTRY:-\${STRAWNT_APP_REGISTRY}}"
export PATH="\${PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="\${PREFIX}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    exec "\$@"
fi
EOF
chmod 755 "${PREFIX}/bin/strawnt-env"
ln -sfn strawnt-env "${PREFIX}/bin/strawwu-env"

log "prefix ready: ${PREFIX}"
log "binary: ${PREFIX}/bin/strawnt ($(du -h "${PREFIX}/bin/strawnt" | awk '{print $1}'))"
"${PREFIX}/bin/strawnt" --version || die "prefix strawnt --version failed"
STRAWNT_APP_REGISTRY="${PREFIX}/var/lib/strawnt/app-registry.json" \
    "${PREFIX}/bin/strawnt" status || die "prefix strawnt status failed"
log "build-prefix PASS"
