#!/usr/bin/env bash
# ntw0-contract.sh — NTW0 contract / legal / StrawWine merge evidence.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/ntw0-contract.json"
mkdir -p "${OUT_DIR}"

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
GIT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

failures=()

require_file() {
    local rel="$1"
    if [[ ! -f "${REPO_ROOT}/${rel}" ]]; then
        failures+=("missing ${rel}")
    fi
}

require_file "docs/decisions/2026-08-07-wine-pivot.md"
require_file "docs/decisions/2026-08-07-strawwine-merge.md"
require_file "docs/legal/WINE-LGPL.md"
require_file "THIRD_PARTY_NOTICES"
require_file "README.md"
require_file "docs/plans/portable-core/USER-GUIDE.md"
require_file "tests/archive/native/README.md"
require_file "archive/native-pe/README.md"

# Product docs must not hard-ban Wine (historical archive wording excepted)
BAN_HITS="$(
    rg -n -i '禁 Wine|不使用 Wine|Wine/Proton not used|禁止.*Wine' \
        "${REPO_ROOT}/README.md" \
        "${REPO_ROOT}/docs/plans/portable-core/USER-GUIDE.md" \
        2>/dev/null \
        | rg -v -i 'archive|歷史|legacy|retired|廢止|lift|powered by' \
        || true
)"
if [[ -n "${BAN_HITS}" ]]; then
    failures+=("product docs still hard-ban Wine: ${BAN_HITS}")
fi

for f in README.md docs/plans/portable-core/USER-GUIDE.md; do
    if ! rg -qi 'powered by Wine|execution_backend=wine|backend=wine' "${REPO_ROOT}/${f}"; then
        failures+=("${f} missing wine / powered by Wine honesty")
    fi
done

if ! rg -qi 'merge_c|C 合併|Policy C|merge_c' "${REPO_ROOT}/docs/decisions/2026-08-07-strawwine-merge.md"; then
    failures+=("strawwine merge ADR missing merge_c")
fi

if ! rg -qi 'lift_ban|廢止' "${REPO_ROOT}/docs/decisions/2026-08-07-wine-pivot.md"; then
    failures+=("wine pivot ADR missing lift_ban")
fi

if ! rg -qi 'Electron|hub/' "${REPO_ROOT}/docs/decisions/2026-08-07-wine-pivot.md" \
    && ! rg -qi 'Electron' "${REPO_ROOT}/docs/decisions/2026-08-07-strawwine-merge.md"; then
    failures+=("ADRs missing Electron hub lock")
fi

if ! rg -qi 'git-lfs' "${REPO_ROOT}/docs/decisions/2026-08-07-wine-pivot.md"; then
    failures+=("wine pivot ADR missing git-lfs")
fi

STATUS="PASS"
if [[ "${#failures[@]}" -gt 0 ]]; then
    STATUS="FAIL"
fi

python3 - "${OUT_JSON}" "${STATUS}" "${VERSION}" "${GIT_HEAD}" "${TS}" "${failures[@]+${failures[@]}}" <<'PY'
import json, sys
from pathlib import Path
out, status, version, git_head, ts = sys.argv[1:6]
failures = sys.argv[6:]
doc = {
    "schema": "strawnt-ntw0-contract/v1",
    "stage": "ntw0-contract-legal",
    "status": status,
    "product": "StrawNT",
    "version": version,
    "generated_at": ts,
    "git_head": git_head,
    "backend": "wine",
    "execution_backend": "wine",
    "engine": "proton-ge",
    "strawwine_policy": "merge_c",
    "hub": "electron",
    "ge_distribution": "git-lfs",
    "claims": {
        "wine_ban_policy": "lift_ban",
        "engine": "proton-ge",
        "strawwine_policy": "merge_c",
        "hub": "electron",
        "ge_distribution": "git-lfs",
        "powered_by_wine": True,
        "native_default_retired": True,
        "full_windows_claimed": False,
        "ranked_anticheat_claimed": False,
        "ge_tree_downloaded_in_ntw0": False,
    },
    "artifacts": {
        "adr_wine_pivot": "docs/decisions/2026-08-07-wine-pivot.md",
        "adr_strawwine_merge": "docs/decisions/2026-08-07-strawwine-merge.md",
        "legal_wine_lgpl": "docs/legal/WINE-LGPL.md",
        "third_party_notices": "THIRD_PARTY_NOTICES",
        "native_archive": "tests/archive/native/README.md",
    },
    "failures": failures,
}
Path(out).write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps({"status": status, "failures": failures}, ensure_ascii=False))
if status != "PASS":
    raise SystemExit(1)
PY

echo "wrote ${OUT_JSON}"
