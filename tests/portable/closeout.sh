#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# closeout.sh — Portable Core A+3 pc5 closeout evidence generator.
# Validates prior stage evidence, docs, artifacts/SHA256, and main merge;
# writes tests/portable/output/closeout.json (top-level status=PASS|FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/closeout.json"
PORTABLE_DOCS="${REPO_ROOT}/docs/plans/portable-core"
SUMS="${OUT_DIR}/SHA256SUMS"
ARTIFACTS_JSON="${PORTABLE_DOCS}/artifacts.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
SKIP_MERGE=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: closeout.sh [--dry-run] [--skip-merge-check] [-h|--help]

Portable Core A+3 closeout (pc5).

  --dry-run             Check required paths only; write FAIL if incomplete
  --skip-merge-check    Do not require origin/main to contain HEAD
  -h, --help            Show this help

PASS: prior stages evidence OK, docs+artifacts+SHA256 present,
      origin/main contains this tip (unless --skip-merge-check),
      ${OUT_JSON} top-level status=PASS.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --skip-merge-check) SKIP_MERGE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "ERROR: unknown arg: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

log() { echo "[closeout] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

json_status() {
    local f="$1"
    [[ -f "$f" ]] || { echo "MISSING"; return; }
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status","?"))' "$f" 2>/dev/null || echo "INVALID"
}

write_closeout() {
    local status="$1"
    mkdir -p "${OUT_DIR}"
    python3 - "$OUT_JSON" "$status" "$VERSION" "$SKIP_MERGE" <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path

out, status, version, skip_merge = sys.argv[1:5]
# closeout.json lives at tests/portable/output/ → parents[3] = repo root
repo = Path(out).resolve().parents[3]
portable = repo / "docs" / "plans" / "portable-core"
out_dir = Path(out).parent

def jq_status(path: Path) -> str:
    if not path.is_file():
        return "MISSING"
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("status", "?")
    except Exception:
        return "INVALID"

def git(*args: str) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()
    except Exception:
        return ""

head = git("rev-parse", "HEAD")
branch = git("rev-parse", "--abbrev-ref", "HEAD")
origin_main = git("rev-parse", "origin/main")
merged = False
if head and origin_main:
    try:
        subprocess.check_call(
            ["git", "-C", str(repo), "merge-base", "--is-ancestor", head, "origin/main"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        merged = True
    except Exception:
        merged = False

stages = {
    "pc0-portable-scaffold": {
        "status": "PASS" if (portable / "A3-cross-distro-core.md").is_file()
            and (portable / "inventory.json").is_file() else "FAIL",
        "evidence": [
            "docs/plans/portable-core/A3-cross-distro-core.md",
            "docs/plans/portable-core/inventory.json",
            "components/packaging/portable/README.md",
        ],
    },
    "pc1-self-contained-prefix": {
        "status": jq_status(out_dir / "smoke-prefix.json"),
        "evidence": ["tests/portable/output/smoke-prefix.json"],
    },
    "pc2-appimage": {
        "status": jq_status(out_dir / "smoke-appimage.json"),
        "evidence": [
            "tests/portable/output/smoke-appimage.json",
            "tests/portable/output/SHA256SUMS",
        ],
    },
    "pc3-flatpak": {
        "status": jq_status(out_dir / "smoke-flatpak.json"),
        "evidence": [
            "tests/portable/output/smoke-flatpak.json",
            "components/packaging/portable/flatpak/org.strawwu.Core.yaml",
        ],
    },
    "pc4-cross-distro-smoke": {
        "status": jq_status(out_dir / "matrix.json"),
        "evidence": ["tests/portable/output/matrix.json"],
    },
    "pc5-closeout": {
        "status": status,
        "evidence": [
            "tests/portable/output/closeout.json",
            "docs/plans/portable-core",
        ],
    },
}

docs = {
    "user_guide": str((portable / "USER-GUIDE.md").relative_to(repo)) if (portable / "USER-GUIDE.md").is_file() else None,
    "user_facing": "docs/user/portable-guide.md" if (repo / "docs/user/portable-guide.md").is_file() else None,
    "closeout_report": str((portable / "closeout-report.md").relative_to(repo)) if (portable / "closeout-report.md").is_file() else None,
    "html": str((portable / "html" / "portable-closeout-report.html").relative_to(repo))
        if (portable / "html" / "portable-closeout-report.html").is_file() else None,
    "kickoff": "docs/plans/kickoff/PC5-closeout.md"
        if (repo / "docs/plans/kickoff/PC5-closeout.md").is_file() else None,
    "artifacts_index": "docs/plans/portable-core/artifacts.json"
        if (portable / "artifacts.json").is_file() else None,
}

sha256_path = out_dir / "SHA256SUMS"
sha256_ok = sha256_path.is_file() and sha256_path.stat().st_size > 0

doc = {
    "schema": "strawwu-portable-closeout/v1",
    "stage": "pc5-closeout",
    "status": status,
    "version": version,
    "track": "A+3",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "git": {
        "branch": branch,
        "head": head,
        "origin_main": origin_main,
        "merged_to_main": merged,
        "skip_merge_check": skip_merge == "1",
    },
    "stages": stages,
    "docs": docs,
    "artifacts": {
        "index": docs.get("artifacts_index"),
        "sha256sums": "tests/portable/output/SHA256SUMS" if sha256_ok else None,
        "sha256_present": sha256_ok,
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "Flatpak PARTIAL kept honest (not rewritten as PASS)",
        "ISO/T1 main worktree not modified",
    ],
}

out_path = Path(out)
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"wrote {out_path} status={status}")
PY
}

# --- checks ---
failures=()

require_file() {
    local p="$1"
    [[ -f "${REPO_ROOT}/${p}" ]] || failures+=("missing ${p}")
}

require_file "docs/plans/portable-core/A3-cross-distro-core.md"
require_file "docs/plans/portable-core/inventory.json"
require_file "docs/plans/portable-core/USER-GUIDE.md"
require_file "docs/plans/portable-core/closeout-report.md"
require_file "docs/plans/portable-core/artifacts.json"
require_file "docs/plans/kickoff/PC5-closeout.md"
require_file "docs/user/portable-guide.md"
require_file "components/packaging/portable/README.md"
require_file "tests/portable/output/smoke-prefix.json"
require_file "tests/portable/output/smoke-appimage.json"
require_file "tests/portable/output/smoke-flatpak.json"
require_file "tests/portable/output/matrix.json"
require_file "tests/portable/output/SHA256SUMS"

s1="$(json_status "${OUT_DIR}/smoke-prefix.json")"
s2="$(json_status "${OUT_DIR}/smoke-appimage.json")"
s3="$(json_status "${OUT_DIR}/smoke-flatpak.json")"
s4="$(json_status "${OUT_DIR}/matrix.json")"

[[ "$s1" == "PASS" ]] || failures+=("smoke-prefix status=${s1}")
[[ "$s2" == "PASS" ]] || failures+=("smoke-appimage status=${s2}")
[[ "$s3" == "PASS" || "$s3" == "PARTIAL" ]] || failures+=("smoke-flatpak status=${s3}")
[[ "$s4" == "PASS" ]] || failures+=("matrix status=${s4}")

# matrix distro count
distro_n="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(max(len(d.get("distros") or []), len(d.get("results") or [])))' "${OUT_DIR}/matrix.json" 2>/dev/null || echo 0)"
[[ "${distro_n}" -ge 3 ]] || failures+=("matrix distros=${distro_n} (<3)")

# artifacts.json schema basics
python3 - "${ARTIFACTS_JSON}" <<'PY' || failures+=("artifacts.json invalid")
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8"))
assert d.get("schema") == "strawwu-portable-artifacts/v1", d.get("schema")
arts = d.get("artifacts") or []
assert len(arts) >= 2, "need >=2 artifacts"
for a in arts:
    assert "name" in a and "sha256" in a and "kind" in a, a
print("artifacts.json ok", len(arts))
PY

# SHA256SUMS non-empty + at least two lines
sums_lines="$(grep -cE '^[0-9a-f]{64} ' "${SUMS}" 2>/dev/null || echo 0)"
[[ "${sums_lines}" -ge 2 ]] || failures+=("SHA256SUMS entries=${sums_lines}")

# Render HTML if renderer present
if [[ -f "${REPO_ROOT}/tests/portable/render-closeout-html.py" ]]; then
    python3 "${REPO_ROOT}/tests/portable/render-closeout-html.py" || failures+=("render-closeout-html failed")
fi
require_file "docs/plans/portable-core/html/portable-closeout-report.html"

# Merge check
merged=0
if [[ "${SKIP_MERGE}" -eq 0 ]]; then
    git -C "${REPO_ROOT}" fetch origin main >/dev/null 2>&1 || true
    if git -C "${REPO_ROOT}" rev-parse origin/main >/dev/null 2>&1; then
        if git -C "${REPO_ROOT}" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
            merged=1
            log "origin/main contains HEAD (merged)"
        else
            failures+=("HEAD not merged into origin/main")
        fi
    else
        failures+=("origin/main missing")
    fi
else
    log "merge check skipped"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run: failures=${#failures[@]}"
    for f in "${failures[@]+"${failures[@]}"}"; do log "  - $f"; done
fi

final_status="PASS"
if [[ "${#failures[@]}" -gt 0 ]]; then
    final_status="FAIL"
    log "FAIL reasons:"
    for f in "${failures[@]}"; do log "  - $f"; done
fi

write_closeout "${final_status}"

if [[ "${final_status}" != "PASS" ]]; then
    exit 1
fi
log "closeout PASS version=${VERSION}"
exit 0
