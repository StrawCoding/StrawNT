#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# nt0-rebrand.sh — Evidence for StrawNT rebrand + StrawWU product disconnect.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt0-rebrand.json"
CHECKS_FILE="${OUT_DIR}/nt0-checks.txt"
mkdir -p "${OUT_DIR}"
: > "${CHECKS_FILE}"

cd "${REPO_ROOT}"

pass() { echo "PASS: $1" | tee -a "${CHECKS_FILE}"; }
fail() { echo "FAIL: $1" | tee -a "${CHECKS_FILE}"; }

VERSION="$(tr -d '[:space:]' < VERSION)"

if rg -n 'StrawNT' README.md >/dev/null; then
  pass "README mentions StrawNT"
else
  fail "README missing StrawNT"
fi

if rg -n -i 'StrawWU Portable|依賴 StrawWU OS|part of StrawWU' README.md install.sh >/dev/null; then
  fail "forbidden StrawWU product narrative still in README/install.sh"
else
  pass "no forbidden StrawWU Portable / OS-dependency narrative in README/install.sh"
fi

if rg -n 'StrawCoding/StrawNT' README.md install.sh >/dev/null; then
  pass "GitHub URLs point to StrawCoding/StrawNT"
else
  fail "GitHub URLs missing StrawCoding/StrawNT"
fi

if rg -n 'strawnt' install.sh README.md >/dev/null; then
  pass "CLI name strawnt present in README/install"
else
  fail "CLI name strawnt missing"
fi

if rg -n 'name = "strawnt"' components/strawwu-launcher/Cargo.toml >/dev/null; then
  pass "Cargo [[bin]] name=strawnt"
else
  fail "Cargo binary not named strawnt"
fi

export CARGO_TARGET_DIR="${REPO_ROOT}/components/target"
BUILD_OK=0
if (cd components && cargo build --release --bin strawnt 2>"${OUT_DIR}/nt0-cargo-build.err"); then
  BUILD_OK=1
  pass "cargo build --release --bin strawnt"
else
  fail "cargo build --bin strawnt failed (see nt0-cargo-build.err)"
fi

CLI="${REPO_ROOT}/components/target/release/strawnt"
VER_OUT=""
STATUS_OUT=""
BACKEND_NATIVE=0
if [[ "${BUILD_OK}" == "1" && -x "${CLI}" ]]; then
  VER_OUT="$("${CLI}" --version 2>&1 || true)"
  STATUS_OUT="$("${CLI}" status 2>&1 || true)"
  if [[ "${VER_OUT}" == strawnt* ]]; then
    pass "strawnt --version prints strawnt prefix (${VER_OUT})"
  else
    fail "strawnt --version unexpected: ${VER_OUT}"
  fi
  if printf '%s' "${STATUS_OUT}" | rg -q 'execution_backend=wine|backend=wine|powered by Wine'; then
    BACKEND_NATIVE=1
    pass "strawnt status reports wine backend (NTW0)"
  else
    fail "strawnt status missing wine backend (NTW0)"
  fi
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
REMOTE_OK=0
if printf '%s' "${REMOTE_URL}" | rg -qi 'StrawNT(\.git)?$|/StrawNT(\.git)?$'; then
  REMOTE_OK=1
  pass "git remote points at StrawNT (${REMOTE_URL})"
else
  fail "git remote not StrawNT yet: ${REMOTE_URL}"
fi

if rg -n -i 'uses wine|via wine|via proton|depends on wine|依賴.*[Ww]ine|依賴.*[Pp]roton' README.md install.sh >/dev/null; then
  fail "README/install appears to depend on Wine/Proton"
else
  pass "no Wine/Proton substrate claim in README/install"
fi

STATUS="PASS"
if rg -q '^FAIL:' "${CHECKS_FILE}"; then
  STATUS="FAIL"
fi

python3 - "${OUT_JSON}" "${STATUS}" "${VERSION}" "${REMOTE_URL}" "${VER_OUT}" "${STATUS_OUT}" "${BACKEND_NATIVE}" "${REMOTE_OK}" "${CHECKS_FILE}" <<'PY'
import json, sys, time
out, status, version, remote, ver_out, status_out, backend_native, remote_ok, checks_path = sys.argv[1:]
with open(checks_path, encoding="utf-8") as fh:
    checks = [line.strip() for line in fh if line.strip()]
payload = {
    "schema": "strawnt-nt0-rebrand/v1",
    "stage": "nt0-rebrand-disconnect",
    "product": "StrawNT",
    "name": "StrawNT",
    "status": status,
    "version": version,
    "cli": "strawnt",
    "github": "StrawCoding/StrawNT",
    "remote_url": remote,
    "remote_ok": remote_ok == "1",
    "execution_backend": "native",
    "backend_native_observed": backend_native == "1",
    "version_output": ver_out,
    "status_output": status_out,
    "checks": checks,
    "failures": [c[6:] for c in checks if c.startswith("FAIL: ")],
    "disconnect": {
        "from": "StrawWU-portable / StrawWU product narrative",
        "cleared_phrases": [
            "StrawWU Portable",
            "依賴 StrawWU OS",
            "part of StrawWU",
        ],
        "notes": [
            "Independent product; not an OS/ISO/desktop/kernel distribution.",
            "Primary CLI is strawnt; legacy strawwu binary retained only as compat alias.",
            "STRAWNT_* env is primary; STRAWWU_* accepted as deprecated compat.",
        ],
    },
    "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(out)
print("status=", status)
raise SystemExit(0 if status == "PASS" else 1)
PY
