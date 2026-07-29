#!/usr/bin/env bash
# build-prefix.sh — Produce a self-contained $STRAWWU_PREFIX for Portable Core (pc1).
# Does not install or depend on system strawwu-* deb packages.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
COMPONENTS_DIR="${REPO_ROOT}/components"
VERSION="${STRAWWU_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
PREFIX="${STRAWWU_PREFIX:-${SCRIPT_DIR}/prefix}"
WITH_HUB="${STRAWWU_PORTABLE_WITH_HUB:-0}"
BUNDLE_HOST_LIBS="${STRAWWU_PORTABLE_BUNDLE_LIBS:-1}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[portable-prefix] $*"; }

command -v cargo >/dev/null 2>&1 || die "cargo not found — install Rust toolchain"
command -v python3 >/dev/null 2>&1 || die "python3 required"

log "building strawwu ${VERSION} → ${PREFIX}"

mkdir -p "${PREFIX}/bin" "${PREFIX}/lib" "${PREFIX}/share/strawwu" \
    "${PREFIX}/share/doc/strawwu-portable" "${PREFIX}/var/lib/strawwu"

# Link with $ORIGIN/../lib rpath so bundled .so resolve relative to the binary.
export CARGO_TARGET_DIR="${COMPONENTS_DIR}/target"
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-rpath,\$ORIGIN/../lib"

cd "${COMPONENTS_DIR}"
cargo build --release --bin strawwu

BINARY="${COMPONENTS_DIR}/target/release/strawwu"
[[ -x "${BINARY}" ]] || die "strawwu binary missing at ${BINARY}"

install -m 755 "${BINARY}" "${PREFIX}/bin/strawwu"
# Keep a non-stripped copy for debugging only when STRAWWU_PORTABLE_KEEP_DEBUG=1
if [[ "${STRAWWU_PORTABLE_KEEP_DEBUG:-0}" != "1" ]]; then
    strip "${PREFIX}/bin/strawwu" 2>/dev/null || true
fi

# Bundle non-base host shared libraries (Vulkan/Pulse/etc. if linked).
# Always leave glibc / libgcc / loader to the host — those are ABI baseline.
if [[ "${BUNDLE_HOST_LIBS}" == "1" ]]; then
    mapfile -t NEEDED < <(ldd "${PREFIX}/bin/strawwu" 2>/dev/null | awk '
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
    patchelf --set-rpath '$ORIGIN/../lib' "${PREFIX}/bin/strawwu" 2>/dev/null \
        || log "patchelf rpath skipped (binary may already embed \$ORIGIN)"
fi

# Wincompat baseline + empty local registry (no /var/lib system dependency).
if [[ -d "${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat" ]]; then
    mkdir -p "${PREFIX}/share/strawwu/wincompat"
    cp -a "${REPO_ROOT}/os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/." \
        "${PREFIX}/share/strawwu/wincompat/"
fi

cat > "${PREFIX}/var/lib/strawwu/app-registry.json" <<'EOF'
{
  "schema_version": "1.0",
  "apps": []
}
EOF

# Manifest describing what this prefix contains.
python3 - "${PREFIX}" "${VERSION}" "${WITH_HUB}" <<'PY'
import json, os, sys, time
prefix, version, with_hub = sys.argv[1], sys.argv[2], sys.argv[3]
bin_path = os.path.join(prefix, "bin", "strawwu")
libs = sorted(
    f for f in os.listdir(os.path.join(prefix, "lib"))
    if f.endswith(".so") or ".so." in f
) if os.path.isdir(os.path.join(prefix, "lib")) else []
manifest = {
    "schema": "strawwu-portable-prefix/v1",
    "stage": "pc1-self-contained-prefix",
    "version": version,
    "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "prefix": prefix,
    "components": {
        "runtime": "linked-into:strawwu",
        "nt": "linked-into:strawwu",
        "launcher": "bin/strawwu",
        "cli": "linked-into:strawwu",
        "graphics": "linked-into:strawwu",
        "audio": "workspace-crate (static path via runtime when linked)",
        "hub": "bundled" if with_hub == "1" else "optional-skipped",
    },
    "binary": "bin/strawwu",
    "bundled_libs": libs,
    "notes": [
        "Self-contained CLI prefix; does not require system strawwu-* deb packages.",
        "Host glibc / libgcc remain the ABI baseline.",
        "Not a full Windows compatibility claim; no Wine/Proton substrate.",
    ],
}
path = os.path.join(prefix, "share", "strawwu", "portable-prefix.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(path)
PY

# Optional Hub (Electron) — copy sources/notes only unless a built artifact exists.
if [[ "${WITH_HUB}" == "1" ]]; then
    mkdir -p "${PREFIX}/opt/strawwu-hub"
    if [[ -d "${REPO_ROOT}/hub/dist" ]]; then
        cp -a "${REPO_ROOT}/hub/dist/." "${PREFIX}/opt/strawwu-hub/"
        log "bundled hub/dist → opt/strawwu-hub"
    else
        cp -a "${REPO_ROOT}/hub/package.json" "${PREFIX}/opt/strawwu-hub/"
        printf '%s\n' \
            "Hub sources live in repo hub/; build Electron artifact separately for full UI." \
            > "${PREFIX}/opt/strawwu-hub/README.portable.txt"
        log "hub marker installed (no dist/ — optional)"
    fi
fi

cat > "${PREFIX}/share/doc/strawwu-portable/README.txt" <<EOF
StrawWU Portable Core prefix ${VERSION}

Layout:
  bin/strawwu              CLI entry (runtime/nt/launcher/cli/graphics linked in)
  lib/                     Bundled non-baseline shared objects + \$ORIGIN rpath
  share/strawwu/           Baseline + portable-prefix.json
  var/lib/strawwu/         Local app-registry (no system /var/lib required)

Usage:
  export STRAWWU_PREFIX=${PREFIX}
  export STRAWWU_APP_REGISTRY=\$STRAWWU_PREFIX/var/lib/strawwu/app-registry.json
  \$STRAWWU_PREFIX/bin/strawwu --version
  \$STRAWWU_PREFIX/bin/strawwu status

This prefix does not depend on system strawwu-* Debian packages.
EOF

# Wrapper that sets local registry when invoked from prefix.
cat > "${PREFIX}/bin/strawwu-env" <<EOF
#!/usr/bin/env bash
# Activate portable prefix environment (source or exec helper).
PREFIX="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export STRAWWU_PREFIX="\${PREFIX}"
export STRAWWU_APP_REGISTRY="\${STRAWWU_APP_REGISTRY:-\${PREFIX}/var/lib/strawwu/app-registry.json}"
export PATH="\${PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="\${PREFIX}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    exec "\$@"
fi
EOF
chmod 755 "${PREFIX}/bin/strawwu-env"

log "prefix ready: ${PREFIX}"
log "binary: ${PREFIX}/bin/strawwu ($(du -h "${PREFIX}/bin/strawwu" | awk '{print $1}'))"
"${PREFIX}/bin/strawwu" --version || die "prefix strawwu --version failed"
STRAWWU_APP_REGISTRY="${PREFIX}/var/lib/strawwu/app-registry.json" \
    "${PREFIX}/bin/strawwu" status || die "prefix strawwu status failed"
log "build-prefix PASS"
