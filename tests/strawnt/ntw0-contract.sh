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
require_file "docs/plans/kickoff/README.md"

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

# Current component docs must not keep native-default + Wine ban as live product contract
for f in components/README.md components/specs/execution-backends.md; do
    if rg -n -i '禁止 Wine/Proton|禁止 Wine／Proton|禁止 Wine/Proton 作為底層' "${REPO_ROOT}/${f}" \
        | rg -v -i 'archive|歷史|legacy|retired|廢止|lift|靜默改名|powered by' >/dev/null 2>&1; then
        failures+=("${f} still hard-bans Wine as product contract")
    fi
    if rg -n 'native 後端為預設' "${REPO_ROOT}/${f}" >/dev/null 2>&1; then
        failures+=("${f} still declares native as product default")
    fi
done

if ! rg -qi 'execution_backend=wine|backend=wine|powered by Wine' \
    "${REPO_ROOT}/components/README.md"; then
    failures+=("components/README.md missing wine default honesty")
fi

if ! rg -qi 'execution_backend: wine|`wine`' \
    "${REPO_ROOT}/components/specs/execution-backends.md"; then
    failures+=("execution-backends.md missing wine default")
fi

# Kickoff / A3 historical hard contracts must be marked retired
for f in docs/plans/kickoff/NT4-anticheat-honest.md docs/plans/portable-core/A3-cross-distro-core.md; do
    if ! rg -qi '歷史|retired|廢止|legacy|lift' "${REPO_ROOT}/${f}"; then
        failures+=("${f} native-era Wine ban not marked historical/retired")
    fi
done

# Native-era pe verify must not fail product tree solely on Wine markers
if rg -n 'write_fail "wine substrate markers found' \
    "${REPO_ROOT}/tests/portable/smoke-pe-real-exec.sh" >/dev/null 2>&1; then
    failures+=("smoke-pe-real-exec.sh still fails on wine substrate markers")
fi
if ! rg -qi 'LEGACY/ARCHIVE|lift_ban|skip wine-substrate' \
    "${REPO_ROOT}/tests/portable/smoke-pe-real-exec.sh"; then
    failures+=("smoke-pe-real-exec.sh missing NTW0 legacy/lift marker")
fi

# Makefile must not expose native-era pe/gx/nt as general product targets
if rg -n '^test-portable-pe-closeout:|^test-portable-gx-graphics:|^test-portable-gx-closeout:|^test-strawnt-nt5-closeout:|^test-strawnt-nt6-openable:' \
    "${REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    failures+=("Makefile still exposes native-era pe/gx/nt as general product targets")
fi
if ! rg -n '^test-legacy-portable-pe-closeout:' "${REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    failures+=("Makefile missing test-legacy-portable-pe-closeout")
fi
if ! rg -n '^test-legacy-strawnt-nt6-openable:' "${REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    failures+=("Makefile missing test-legacy-strawnt-nt6-openable")
fi
if ! rg -n '^test-legacy-strawnt-nt3-launchers:' "${REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    failures+=("Makefile missing test-legacy-strawnt-nt3-launchers")
fi
if ! rg -qi 'Legacy/archive native-era' "${REPO_ROOT}/Makefile"; then
    failures+=("Makefile help missing Legacy/archive native-era section")
fi

# nt3 must not fail product tree solely on Wine markers
if rg -n 'write_fail "wine substrate markers found' \
    "${REPO_ROOT}/tests/strawnt/nt3-real-launchers.sh" >/dev/null 2>&1; then
    failures+=("nt3-real-launchers.sh still fails on wine substrate markers")
fi
if ! rg -qi 'skip wine-substrate|lift_ban' \
    "${REPO_ROOT}/tests/strawnt/nt3-real-launchers.sh"; then
    failures+=("nt3-real-launchers.sh missing NTW0 wine-substrate skip")
fi

# components Phase 6 must be labeled legacy — not general product Wine acceptance
if ! rg -qi 'Legacy/archive|test-legacy-wincompat' \
    "${REPO_ROOT}/components/Makefile"; then
    failures+=("components/Makefile missing legacy wincompat labeling")
fi
if rg -n 'Full Phase 6 acceptance' "${REPO_ROOT}/components/Makefile" \
    | rg -v -i 'legacy|archive|NOT|not product' >/dev/null 2>&1; then
    failures+=("components/Makefile still advertises Full Phase 6 acceptance as product")
fi
if ! rg -qi 'Legacy|archive|test-legacy-wincompat' \
    "${REPO_ROOT}/components/README.md"; then
    failures+=("components/README.md missing legacy wincompat labeling")
fi

# golden-apps live contract must default to wine
if ! jq -e '[.apps[].backend_default] | all(. == "wine")' \
    "${REPO_ROOT}/components/tests/wincompat/golden-apps.json" >/dev/null 2>&1; then
    failures+=("golden-apps.json backend_default is not wine for all apps")
fi

# runtime must accept wine as ExecutionBackend
if ! rg -n 'Wine' "${REPO_ROOT}/components/strawwu-runtime/src/session.rs" >/dev/null 2>&1; then
    failures+=("ExecutionBackend missing Wine variant")
fi
if ! rg -n '"wine"' "${REPO_ROOT}/components/strawwu-launcher/src/loader.rs" >/dev/null 2>&1; then
    failures+=("launcher LaunchRequest does not allow wine backend")
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
        "opencode_gaps_addressed": [
            "components/README.md + execution-backends.md live contract flipped to wine",
            "kickoff/A3 historical Wine ban marked retired",
            "smoke-pe-real-exec wine marker product-tree fail removed",
            "Makefile native-era pe/gx/nt renamed to test-legacy-* (not general product targets)",
            "execution-backends architecture diagram wine/GE primary",
            "nt6-openable moved to test-legacy-strawnt-nt6-openable (not product target)",
            "components Phase 6 → test-legacy-wincompat; golden-apps backend_default=wine",
            "nt3-real-launchers wine substrate product-tree write_fail removed",
            "ExecutionBackend::Wine + launcher open/install product default wine",
        ],
    },
    "artifacts": {
        "adr_wine_pivot": "docs/decisions/2026-08-07-wine-pivot.md",
        "adr_strawwine_merge": "docs/decisions/2026-08-07-strawwine-merge.md",
        "legal_wine_lgpl": "docs/legal/WINE-LGPL.md",
        "third_party_notices": "THIRD_PARTY_NOTICES",
        "native_archive": "tests/archive/native/README.md",
        "kickoff_index": "docs/plans/kickoff/README.md",
    },
    "failures": failures,
}
Path(out).write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps({"status": status, "failures": failures}, ensure_ascii=False))
if status != "PASS":
    raise SystemExit(1)
PY

echo "wrote ${OUT_JSON}"
