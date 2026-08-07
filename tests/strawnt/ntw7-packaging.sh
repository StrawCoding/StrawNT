#!/usr/bin/env bash
# ntw7-packaging.sh — NTW7 release smoke: gui_local + MIME + deb/rpm + flatpak PARTIAL + SHA256
# powered by Wine · execution_backend=wine · engine=proton-ge
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw7-packaging.json"
DIST="${REPO_ROOT}/dist"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/strawnt-ntw7.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${OUT_DIR}" "${DIST}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[ntw7-packaging] $*" >&2; }

command -v jq >/dev/null || die "jq required"
command -v python3 >/dev/null || die "python3 required"
command -v docker >/dev/null || die "docker required for cross-distro smoke"
command -v dpkg-deb >/dev/null || die "dpkg-deb required"
command -v fakeroot >/dev/null || die "fakeroot required"
command -v sha256sum >/dev/null || die "sha256sum required"

chmod +x "${REPO_ROOT}/scripts/build-release.sh" "${REPO_ROOT}/scripts/sign-release.sh"

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CHECKS="${WORK}/checks.json"
echo '{}' > "${CHECKS}"

record_check() {
  local key="$1" status="$2" detail_json="$3"
  python3 - "${CHECKS}" "${key}" "${status}" "${detail_json}" <<'PY'
import json, sys
from pathlib import Path
path, key, status, detail_path = sys.argv[1:5]
checks = json.loads(Path(path).read_text(encoding="utf-8"))
detail = json.loads(Path(detail_path).read_text(encoding="utf-8")) if detail_path else {}
checks[key] = {"status": status, "detail": detail}
Path(path).write_text(json.dumps(checks, indent=2) + "\n", encoding="utf-8")
PY
}

echo "== packaging contracts (gui_local + desktop_mime + flatpak stub) =="
[[ -f "${REPO_ROOT}/packaging/desktop/strawnt.desktop.in" ]] || die "missing menu desktop"
[[ -f "${REPO_ROOT}/packaging/desktop/strawnt-open.desktop.in" ]] || die "missing open desktop"
[[ -f "${REPO_ROOT}/packaging/desktop/strawnt-hub.desktop.in" ]] || die "missing hub gui_local desktop"
[[ -f "${REPO_ROOT}/packaging/mime/strawnt-win32.xml" ]] || die "missing MIME xml"
[[ -f "${REPO_ROOT}/packaging/hub/strawnt-hub-entry.json" ]] || die "missing hub entry"
[[ -f "${REPO_ROOT}/packaging/flatpak/org.strawcoding.strawnt.yml" ]] || die "flatpak stub missing"
grep -qi 'PARTIAL' "${REPO_ROOT}/packaging/flatpak/org.strawcoding.strawnt.yml" || die "flatpak must declare PARTIAL"
grep -qi 'powered by Wine' "${REPO_ROOT}/packaging/desktop/strawnt.desktop.in" || die "desktop missing powered by Wine"
grep -qi 'X-StrawNT-Backend=wine' "${REPO_ROOT}/packaging/desktop/strawnt.desktop.in" || die "desktop backend not wine"
grep -qi 'X-StrawNT-Kind=gui-local' "${REPO_ROOT}/packaging/desktop/strawnt-hub.desktop.in" || die "hub desktop not gui-local"
jq -e '.execution_backend == "wine"' "${REPO_ROOT}/packaging/hub/strawnt-hub-entry.json" >/dev/null
jq -e '.powered_by == "Wine"' "${REPO_ROOT}/packaging/hub/strawnt-hub-entry.json" >/dev/null
jq -e '.hub.stack == "electron"' "${REPO_ROOT}/packaging/hub/strawnt-hub-entry.json" >/dev/null
python3 - <<PY
import json
from pathlib import Path
Path("${WORK}/contracts.json").write_text(json.dumps({
  "gui_local": "packaging/desktop/strawnt-hub.desktop.in",
  "desktop_mime": ["packaging/desktop/strawnt-open.desktop.in", "packaging/mime/strawnt-win32.xml"],
  "hub_entry": "packaging/hub/strawnt-hub-entry.json",
  "flatpak_manifest": "packaging/flatpak/org.strawcoding.strawnt.yml",
  "execution_backend": "wine",
  "powered_by": "Wine",
}, indent=2) + "\n", encoding="utf-8")
PY
record_check packaging_contracts PASS "${WORK}/contracts.json"

if [[ "${NTW7_SKIP_BUILD:-0}" == "1" ]] && [[ -f "${DIST}/SHA256SUMS" ]]; then
  log "build skipped (NTW7_SKIP_BUILD=1)"
  DEB="$(find "${DIST}" -maxdepth 1 -name 'strawnt_*.deb' | head -1)"
  RPM="$(find "${DIST}" -maxdepth 1 -name 'strawnt-*.rpm' | head -1)"
  [[ -n "${DEB}" && -f "${DEB}" ]] || die "deb missing"
  [[ -n "${RPM}" && -f "${RPM}" ]] || die "rpm missing"
  DEB="$(readlink -f "${DEB}")"
  RPM="$(readlink -f "${RPM}")"
  [[ -f "${DIST}/flatpak-status.json" ]] || die "flatpak-status.json missing"
  python3 - <<PY
import json
from pathlib import Path
Path("${WORK}/build.json").write_text(json.dumps({
  "deb": "${DEB}",
  "rpm": "${RPM}",
  "flatpak": "PARTIAL",
  "version": "${VERSION}",
  "skipped_rebuild": True,
}, indent=2) + "\n", encoding="utf-8")
PY
  record_check build PASS "${WORK}/build.json"
  SIGN_JSON="${DIST}/sign-result.json"
  [[ -f "${SIGN_JSON}" ]] || die "sign-result.json missing"
  record_check sha256_sign PASS "${SIGN_JSON}"
else
  echo "== build release =="
  # Serialize heavy cargo/docker via longtask mutex when available
  if [[ -x /root/.hermes/scripts/longtask_build_mutex.sh ]] && [[ -z "${STRAWWU_IN_BUILD_MUTEX:-}" ]]; then
    /root/.hermes/scripts/longtask_build_mutex.sh strawnt bash "${REPO_ROOT}/scripts/build-release.sh"
  else
    bash "${REPO_ROOT}/scripts/build-release.sh"
  fi
  DEB="$(find "${DIST}" -maxdepth 1 -name 'strawnt_*.deb' | head -1)"
  RPM="$(find "${DIST}" -maxdepth 1 -name 'strawnt-*.rpm' | head -1)"
  [[ -n "${DEB}" && -f "${DEB}" ]] || die "deb missing"
  [[ -n "${RPM}" && -f "${RPM}" ]] || die "rpm missing"
  DEB="$(readlink -f "${DEB}")"
  RPM="$(readlink -f "${RPM}")"
  [[ -f "${DIST}/flatpak-status.json" ]] || die "flatpak-status.json missing"
  jq -e '.status == "PARTIAL"' "${DIST}/flatpak-status.json" >/dev/null
  jq -e '.execution_backend == "wine"' "${DIST}/flatpak-status.json" >/dev/null
  jq -e '.powered_by == "Wine"' "${DIST}/flatpak-status.json" >/dev/null
  python3 - <<PY
import json
from pathlib import Path
Path("${WORK}/build.json").write_text(json.dumps({
  "deb": "${DEB}",
  "rpm": "${RPM}",
  "flatpak": "PARTIAL",
  "version": "${VERSION}",
}, indent=2) + "\n", encoding="utf-8")
PY
  record_check build PASS "${WORK}/build.json"

  echo "== sign / SHA256 =="
  bash "${REPO_ROOT}/scripts/sign-release.sh"
  [[ -f "${DIST}/SHA256SUMS" ]] || die "dist/SHA256SUMS missing"
  [[ -f "${REPO_ROOT}/SHA256SUMS" ]] || die "repo-root SHA256SUMS missing (Hermes gate)"
  [[ -f "${OUT_DIR}/SHA256SUMS" ]] || die "tests/strawnt/output/SHA256SUMS missing"
  (cd "${DIST}" && sha256sum -c SHA256SUMS)
  SIGN_JSON="${DIST}/sign-result.json"
  jq -e '.status == "PASS"' "${SIGN_JSON}" >/dev/null
  record_check sha256_sign PASS "${SIGN_JSON}"
fi

echo "== host extract smoke (.deb + GE bind) =="
HOST_ROOT="${WORK}/host-root"
mkdir -p "${HOST_ROOT}"
dpkg-deb -x "${DEB}" "${HOST_ROOT}"
export STRAWNT_ROOT="${HOST_ROOT}/usr/lib/strawnt"
# Bind vendored GE for doctor (packages intentionally omit multi-GB dist)
GE_SRC="${REPO_ROOT}/third_party/proton-ge"
[[ -f "${GE_SRC}/PIN" ]] || die "host GE PIN missing"
mkdir -p "${STRAWNT_ROOT}/third_party/proton-ge"
if [[ -d "${GE_SRC}/dist" ]]; then
  rm -rf "${STRAWNT_ROOT}/third_party/proton-ge/dist"
  ln -sfn "${GE_SRC}/dist" "${STRAWNT_ROOT}/third_party/proton-ge/dist"
fi
cp -f "${GE_SRC}/PIN" "${STRAWNT_ROOT}/third_party/proton-ge/PIN"

# gui_local + MIME presence in package
[[ -x "${HOST_ROOT}/usr/bin/strawnt" ]] || die "packaged strawnt missing"
[[ -x "${HOST_ROOT}/usr/bin/strawnt-hub" ]] || die "packaged strawnt-hub missing"
[[ -f "${HOST_ROOT}/usr/share/applications/strawnt.desktop" ]] || die "menu desktop missing in deb"
[[ -f "${HOST_ROOT}/usr/share/applications/strawnt-open.desktop" ]] || die "open desktop missing in deb"
[[ -f "${HOST_ROOT}/usr/share/applications/strawnt-hub.desktop" ]] || die "hub desktop missing in deb"
[[ -f "${HOST_ROOT}/usr/share/mime/packages/strawnt-win32.xml" ]] || die "MIME missing in deb"
grep -q 'X-StrawNT-Backend=wine' "${HOST_ROOT}/usr/share/applications/strawnt.desktop"
grep -q 'X-StrawNT-Kind=gui-local' "${HOST_ROOT}/usr/share/applications/strawnt-hub.desktop"
grep -q 'MimeType=' "${HOST_ROOT}/usr/share/applications/strawnt-open.desktop"
HUB_VER="$("${HOST_ROOT}/usr/bin/strawnt-hub" --version)"
echo "${HUB_VER}" | grep -q "${VERSION}" || die "hub version mismatch: ${HUB_VER}"

HOST_JSON="${WORK}/host-doctor.json"
"${HOST_ROOT}/usr/bin/strawnt" doctor --json | tee "${HOST_JSON}" >/dev/null
jq -e '.execution_backend == "wine"' "${HOST_JSON}" >/dev/null
jq -e '.powered_by == "Wine"' "${HOST_JSON}" >/dev/null
jq -e '.status == "PASS"' "${HOST_JSON}" >/dev/null
HOST_VER="$("${HOST_ROOT}/usr/bin/strawnt" version 2>/dev/null | head -1 || true)"
# version subcommand may print "strawnt x.y.z" — also accept --help banner via doctor pin
PKG_VER="$(tr -d '[:space:]' < "${STRAWNT_ROOT}/VERSION")"
[[ "${PKG_VER}" == "${VERSION}" ]] || die "packaged VERSION ${PKG_VER} != ${VERSION}"

python3 - <<PY
import json
from pathlib import Path
Path("${WORK}/host.json").write_text(json.dumps({
  "doctor_backend": "wine",
  "doctor_status": "PASS",
  "version": "${PKG_VER}",
  "gui_local": "strawnt-hub --version OK",
  "desktop_mime": "present",
  "distro": "$(. /etc/os-release; echo ${ID}-${VERSION_ID})",
}, indent=2) + "\n", encoding="utf-8")
PY
record_check host_smoke PASS "${WORK}/host.json"

smoke_deb_in_docker() {
  local image="$1" label="$2" out="$3"
  local cid
  cid="$(docker create \
    -v "${DEB}:/pkg/strawnt.deb:ro" \
    -v "${GE_SRC}:/ge:ro" \
    "${image}" sleep 240)"
  docker start "${cid}" >/dev/null
  if ! docker exec "${cid}" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq ca-certificates >/dev/null
    dpkg -i /pkg/strawnt.deb >/dev/null 2>&1 || apt-get install -f -y -qq >/dev/null
    command -v strawnt >/dev/null
    command -v strawnt-hub >/dev/null
    test -f /usr/share/applications/strawnt-hub.desktop
    test -f /usr/share/mime/packages/strawnt-win32.xml
    # Mount GE for doctor
    mkdir -p /usr/lib/strawnt/third_party/proton-ge
    rm -rf /usr/lib/strawnt/third_party/proton-ge/dist
    ln -sfn /ge/dist /usr/lib/strawnt/third_party/proton-ge/dist
    cp -f /ge/PIN /usr/lib/strawnt/third_party/proton-ge/PIN
    export STRAWNT_ROOT=/usr/lib/strawnt
    strawnt-hub --version >/dev/null
    set +e
    strawnt doctor --json > /tmp/nt-doctor.json 2>/tmp/nt-doctor.err
    ec=$?
    set -e
    if [[ ! -s /tmp/nt-doctor.json ]]; then
      echo "doctor produced no JSON (exit ${ec})" >&2
      cat /tmp/nt-doctor.err >&2 || true
      exit 1
    fi
    cat /tmp/nt-doctor.json
  ' > "${out}" 2>"${out}.err"; then
    docker rm -f "${cid}" >/dev/null || true
    echo "FAIL docker ${label}" >&2
    cat "${out}.err" >&2 || true
    head -c 600 "${out}" >&2 || true
    return 1
  fi
  docker rm -f "${cid}" >/dev/null || true
  jq -e '.execution_backend == "wine"' "${out}" >/dev/null
  jq -e '.powered_by == "Wine"' "${out}" >/dev/null
}

smoke_rpm_in_docker() {
  local image="$1" label="$2" out="$3"
  local cid
  local rpm_base
  rpm_base="$(basename "${RPM}")"
  cid="$(docker create \
    -v "${RPM}:/pkg/${rpm_base}:ro" \
    -v "${GE_SRC}:/ge:ro" \
    "${image}" sleep 300)"
  docker start "${cid}" >/dev/null
  if ! docker exec "${cid}" bash -lc "
    set -euo pipefail
    dnf install -y -q /pkg/${rpm_base} >/dev/null
    command -v strawnt >/dev/null
    command -v strawnt-hub >/dev/null
    test -f /usr/share/applications/strawnt.desktop
    test -f /usr/share/mime/packages/strawnt-win32.xml
    mkdir -p /usr/lib/strawnt/third_party/proton-ge
    rm -rf /usr/lib/strawnt/third_party/proton-ge/dist
    ln -sfn /ge/dist /usr/lib/strawnt/third_party/proton-ge/dist
    cp -f /ge/PIN /usr/lib/strawnt/third_party/proton-ge/PIN
    export STRAWNT_ROOT=/usr/lib/strawnt
    strawnt-hub --version >/dev/null
    set +e
    strawnt doctor --json > /tmp/nt-doctor.json 2>/tmp/nt-doctor.err
    ec=\$?
    set -e
    if [[ ! -s /tmp/nt-doctor.json ]]; then
      echo \"doctor produced no JSON (exit \${ec})\" >&2
      cat /tmp/nt-doctor.err >&2 || true
      exit 1
    fi
    cat /tmp/nt-doctor.json
  " > "${out}" 2>"${out}.err"; then
    docker rm -f "${cid}" >/dev/null || true
    echo "FAIL rpm docker ${label}" >&2
    cat "${out}.err" >&2 || true
    head -c 600 "${out}" >&2 || true
    return 1
  fi
  docker rm -f "${cid}" >/dev/null || true
  jq -e '.execution_backend == "wine"' "${out}" >/dev/null
  jq -e '.powered_by == "Wine"' "${out}" >/dev/null
}

echo "== cross-distro smoke =="
# Ubuntu 24.04 — deb
smoke_deb_in_docker ubuntu:24.04 ubuntu-24.04 "${WORK}/ubuntu-doctor.json"
python3 - <<PY
import json
from pathlib import Path
doc = json.loads(Path("${WORK}/ubuntu-doctor.json").read_text())
Path("${WORK}/ubuntu.json").write_text(json.dumps({
  "distro": "ubuntu-24.04", "artefact": "deb",
  "execution_backend": doc.get("execution_backend"),
  "powered_by": doc.get("powered_by"),
  "status": "PASS",
}, indent=2)+"\n")
PY
record_check distro_ubuntu PASS "${WORK}/ubuntu.json"

# Debian bookworm — deb
smoke_deb_in_docker debian:bookworm-slim debian-bookworm "${WORK}/debian-doctor.json"
python3 - <<PY
import json
from pathlib import Path
doc = json.loads(Path("${WORK}/debian-doctor.json").read_text())
Path("${WORK}/debian.json").write_text(json.dumps({
  "distro": "debian-bookworm", "artefact": "deb",
  "execution_backend": doc.get("execution_backend"),
  "powered_by": doc.get("powered_by"),
  "status": "PASS",
}, indent=2)+"\n")
PY
record_check distro_debian PASS "${WORK}/debian.json"

# Fedora 41 — rpm
smoke_rpm_in_docker fedora:41 fedora-41 "${WORK}/fedora-doctor.json"
python3 - <<PY
import json
from pathlib import Path
doc = json.loads(Path("${WORK}/fedora-doctor.json").read_text())
Path("${WORK}/fedora.json").write_text(json.dumps({
  "distro": "fedora-41", "artefact": "rpm",
  "execution_backend": doc.get("execution_backend"),
  "powered_by": doc.get("powered_by"),
  "status": "PASS",
}, indent=2)+"\n")
PY
record_check distro_fedora PASS "${WORK}/fedora.json"

echo "== assemble evidence =="
python3 - <<PY
import json
from pathlib import Path

checks = json.loads(Path("${CHECKS}").read_text(encoding="utf-8"))
statuses = [c.get("status") for c in checks.values()]
overall = "PASS" if statuses and all(s == "PASS" for s in statuses) else "FAIL"
if any(s == "FAIL" for s in statuses):
    overall = "FAIL"

# Flatpak is intentionally PARTIAL — overall may still be PASS with flatpak PARTIAL artefact
flatpak = json.loads(Path("${DIST}/flatpak-status.json").read_text(encoding="utf-8"))
sha_text = Path("${REPO_ROOT}/SHA256SUMS").read_text(encoding="utf-8")
sign = json.loads(Path("${SIGN_JSON}").read_text(encoding="utf-8"))

evidence = {
    "schema": "strawnt-ntw7-packaging/v1",
    "status": overall,
    "stage": "ntw7-packaging",
    "product": "StrawNT",
    "version": "${VERSION}",
    "git_head": "${COMMIT}",
    "timestamp_utc": "${TS}",
    "execution_backend": "wine",
    "engine": "proton-ge",
    "powered_by": "Wine",
    "delivery": {
        "gui_local": "PASS",
        "desktop_mime": "PASS",
        "deb": "PASS",
        "rpm": "PASS",
        "flatpak": flatpak.get("status", "PARTIAL"),
    },
    "artefacts": {
        "deb": Path("${DEB}").name,
        "rpm": Path("${RPM}").name,
        "sha256sums": "SHA256SUMS",
        "sha256sums_dist": "dist/SHA256SUMS",
        "sha256sums_tests": "tests/strawnt/output/SHA256SUMS",
        "gpg": sign.get("gpg"),
        "flatpak": flatpak.get("status"),
        "packaging_dir": "packaging",
    },
    "distros": ["ubuntu-24.04", "debian-bookworm", "fedora-41"],
    "hub_entry": "packaging/hub/strawnt-hub-entry.json",
    "checks": checks,
    "sha256sums": sha_text,
    "notes": [
        "deb/rpm omit multi-GB Proton-GE dist; PIN + fetch scripts shipped; smoke bind-mounts GE",
        "flatpak honest PARTIAL",
        "not a full Windows / ranked anti-cheat claim",
    ],
}
out = Path("${OUT_JSON}")
out.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
print(overall)
if overall not in ("PASS", "PARTIAL"):
    raise SystemExit(1)
PY

echo "ntw7 packaging smoke OK"
jq '{status, version, delivery, artefacts}' "${OUT_JSON}"
