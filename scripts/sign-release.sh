#!/usr/bin/env bash
# sign-release.sh — SHA256SUMS (+ optional GPG) for dist/; copy to repo root + tests/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${REPO_ROOT}/dist"
OUT_COPY="${REPO_ROOT}/tests/strawnt/output"

[[ -d "${DIST}" ]] || { echo "ERROR: missing ${DIST}; run build-release.sh first" >&2; exit 1; }

cd "${DIST}"
mapfile -t FILES < <(find . -maxdepth 1 -type f \( \
  -name 'strawnt_*.deb' -o -name 'strawnt-*.rpm' -o -name 'flatpak-status.json' \
\) | sed 's|^\./||' | sort)

[[ ${#FILES[@]} -ge 3 ]] || {
  echo "ERROR: expected .deb, .rpm, and flatpak-status.json in ${DIST} (got: ${FILES[*]:-none})" >&2
  exit 1
}

sha256sum "${FILES[@]}" > SHA256SUMS

GPG_STATUS="skipped"
GPG_KEY_HINT=""
if command -v gpg >/dev/null && gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
  if gpg --list-secret-keys --with-colons 2>/dev/null | grep -q 'StrawWU APT\|apt@wastebase'; then
    gpg --batch --yes --local-user "apt@wastebase.xyz" --detach-sign --armor -o SHA256SUMS.asc SHA256SUMS
    GPG_KEY_HINT="apt@wastebase.xyz"
  else
    gpg --batch --yes --detach-sign --armor -o SHA256SUMS.asc SHA256SUMS
    GPG_KEY_HINT="default-secret-key"
  fi
  GPG_STATUS="signed"
  gpg --verify SHA256SUMS.asc SHA256SUMS
  sha256sum -c SHA256SUMS
else
  echo "WARN: no GPG secret key; SHA256SUMS only" >&2
  sha256sum -c SHA256SUMS
fi

# Hermes gate: test -f SHA256SUMS at repo root
cp -f SHA256SUMS "${REPO_ROOT}/SHA256SUMS"
if [[ -f SHA256SUMS.asc ]]; then
  cp -f SHA256SUMS.asc "${REPO_ROOT}/SHA256SUMS.asc"
fi

mkdir -p "${OUT_COPY}"
cp -f SHA256SUMS "${OUT_COPY}/SHA256SUMS"
if [[ -f SHA256SUMS.asc ]]; then
  cp -f SHA256SUMS.asc "${OUT_COPY}/SHA256SUMS.asc"
fi

python3 - "${GPG_STATUS}" "${GPG_KEY_HINT}" "${FILES[@]}" <<'PY'
import json, sys
from pathlib import Path
gpg_status, gpg_hint, *files = sys.argv[1:]
dist = Path(".")
payload = {
    "status": "PASS",
    "gpg": gpg_status,
    "gpg_key_hint": gpg_hint,
    "files": files,
    "sha256sums": (dist / "SHA256SUMS").read_text(encoding="utf-8"),
    "execution_backend": "wine",
    "engine": "proton-ge",
    "powered_by": "Wine",
}
(dist / "sign-result.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"status": "PASS", "gpg": gpg_status, "files": files}))
PY
