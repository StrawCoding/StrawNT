#!/usr/bin/env bash
# check-version-bump.sh — fail if source changed without VERSION bump.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

BASE="${CHECK_VERSION_BASE:-}"
if [[ -z "${BASE}" ]]; then
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        BASE="$(git merge-base HEAD origin/main 2>/dev/null || echo origin/main)"
    else
        BASE="HEAD~1"
    fi
fi

if ! git rev-parse --verify "${BASE}" >/dev/null 2>&1; then
    echo "check-version-bump: skip (no base ref ${BASE})"
    exit 0
fi

mapfile -t CHANGED < <(git diff --name-only "${BASE}" HEAD)

if [[ ${#CHANGED[@]} -eq 0 ]]; then
    echo "check-version-bump: PASS (no changes)"
    exit 0
fi

IGNORE_PATTERN='^(VERSION$|\.github/workflows/|os-image/output/|tests/boot/output/|.*\.iso$|.*\.log$|docs/technical-references/upstream/)'

needs_bump=0
for f in "${CHANGED[@]}"; do
    if [[ "${f}" =~ ${IGNORE_PATTERN} ]]; then
        continue
    fi
    needs_bump=1
    break
done

if [[ "${needs_bump}" -eq 0 ]]; then
    echo "check-version-bump: PASS (only ignored paths changed)"
    exit 0
fi

if git diff --name-only "${BASE}" HEAD | grep -qx 'VERSION'; then
    old="$(git show "${BASE}:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
    new="$(tr -d '[:space:]' < VERSION)"
    if [[ -n "${old}" && "${old}" == "${new}" ]]; then
        echo "ERROR: VERSION touched but unchanged (${new}) — run: bash scripts/bump-version.sh" >&2
        exit 1
    fi
    echo "check-version-bump: PASS (VERSION ${old:-?} → ${new})"
    exit 0
fi

echo "ERROR: code/docs changed without VERSION bump." >&2
echo "Changed files (sample):" >&2
printf '  - %s\n' "${CHANGED[@]:0:12}" >&2
echo "Run: bash scripts/bump-version.sh && git add VERSION hub/package.json components/Cargo.toml" >&2
exit 1
