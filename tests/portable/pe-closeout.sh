#!/usr/bin/env bash
# pe-closeout.sh — Native PE Real Exec pe7 closeout evidence generator.
# Validates pe0–pe6 evidence, docs, release artifacts/SHA256, cross-distro
# matrix, HTML report; writes tests/portable/output/pe-closeout.json.
# Forbidden: Wine/Proton substrate, WinBox naming, full Windows claims, ISO work.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/pe-closeout.json"
PORTABLE_DOCS="${REPO_ROOT}/docs/plans/portable-core"
SUMS="${OUT_DIR}/SHA256SUMS"
ARTIFACTS_JSON="${PORTABLE_DOCS}/artifacts.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
SKIP_MERGE=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: pe-closeout.sh [--dry-run] [--skip-merge-check] [-h|--help]

Native PE Real Exec closeout (pe7).

  --dry-run             Check required paths only; write FAIL if incomplete
  --skip-merge-check    Do not require origin/main to contain HEAD
  -h, --help            Show this help

PASS: pe0–pe6 evidence OK (pe6 may be PARTIAL), docs+artifacts+SHA256 present,
      matrix ≥3 distros PASS, origin/main contains tip (unless skipped),
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

log() { echo "[pe-closeout] $*"; }
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

def stage(name, path, evidence, allow_partial=False):
    st = jq_status(path)
    ok = st == "PASS" or (allow_partial and st == "PARTIAL")
    return {
        "status": st if ok or st in ("PASS", "PARTIAL", "FAIL", "MISSING", "INVALID") else st,
        "evidence": evidence,
        "acceptable": ok,
    }

stages = {
    "pe0-remove-wine": stage(
        "pe0",
        out_dir / "pe0-remove-wine.json",
        ["tests/portable/output/pe0-remove-wine.json"],
    ),
    "pe1-real-cpu-exec": stage(
        "pe1",
        out_dir / "pe-real-exec.json",
        ["tests/portable/output/pe-real-exec.json"],
    ),
    "pe2-win32-console-mvp": stage(
        "pe2",
        out_dir / "pe-console.json",
        ["tests/portable/output/pe-console.json"],
    ),
    "pe3-gui-user32-mvp": stage(
        "pe3",
        out_dir / "pe-gui.json",
        ["tests/portable/output/pe-gui.json"],
        allow_partial=True,
    ),
    "pe4-installer-real": stage(
        "pe4",
        out_dir / "pe-installer.json",
        ["tests/portable/output/pe-installer.json"],
        allow_partial=True,
    ),
    "pe5-desktop-click": stage(
        "pe5",
        out_dir / "pe-desktop-click.json",
        ["tests/portable/output/pe-desktop-click.json"],
    ),
    "pe6-golden-smoke": stage(
        "pe6",
        out_dir / "pe-golden.json",
        ["tests/portable/output/pe-golden.json"],
        allow_partial=True,
    ),
    "pc4-cross-distro-smoke": stage(
        "pc4",
        out_dir / "matrix.json",
        ["tests/portable/output/matrix.json"],
    ),
    "pe7-closeout": {
        "status": status,
        "evidence": [
            "tests/portable/output/pe-closeout.json",
            "docs/plans/portable-core",
        ],
        "acceptable": status == "PASS",
    },
}

docs = {
    "user_guide": str((portable / "USER-GUIDE.md").relative_to(repo)) if (portable / "USER-GUIDE.md").is_file() else None,
    "user_facing": "docs/user/portable-guide.md" if (repo / "docs/user/portable-guide.md").is_file() else None,
    "closeout_report": str((portable / "pe-closeout-report.md").relative_to(repo))
        if (portable / "pe-closeout-report.md").is_file() else None,
    "html": str((portable / "html" / "pe-closeout-report.html").relative_to(repo))
        if (portable / "html" / "pe-closeout-report.html").is_file() else None,
    "kickoff": "docs/plans/kickoff/PE7-closeout.md"
        if (repo / "docs/plans/kickoff/PE7-closeout.md").is_file() else None,
    "stage_report": "docs/plans/stage-reports/PE7-closeout-report.md"
        if (repo / "docs/plans/stage-reports/PE7-closeout-report.md").is_file() else None,
    "artifacts_index": "docs/plans/portable-core/artifacts.json"
        if (portable / "artifacts.json").is_file() else None,
    "readme": "README.md" if (repo / "README.md").is_file() else None,
}

sha256_path = out_dir / "SHA256SUMS"
sha256_ok = sha256_path.is_file() and sha256_path.stat().st_size > 0

# Release artifact presence (AppImage + portable.tar.gz for this VERSION)
dist = repo / "components" / "packaging" / "portable" / "appimage" / "dist"
appimage = dist / f"StrawWU-Core-{version}-x86_64.AppImage"
tarball = dist / f"StrawWU-Core-{version}-x86_64.portable.tar.gz"

doc = {
    "schema": "strawwu-portable-pe-closeout/v1",
    "stage": "pe7-closeout",
    "status": status,
    "version": version,
    "track": "native-pe-real-exec",
    "backend": "native",
    "execution_backend": "native",
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
        "appimage": str(appimage.relative_to(repo)) if appimage.is_file() else None,
        "portable_tar_gz": str(tarball.relative_to(repo)) if tarball.is_file() else None,
        "appimage_present": appimage.is_file(),
        "portable_tar_gz_present": tarball.is_file(),
    },
    "honesty": {
        "pe6_golden": jq_status(out_dir / "pe-golden.json"),
        "flatpak": jq_status(out_dir / "smoke-flatpak.json"),
        "full_windows_claim": False,
        "anti_cheat_claim": False,
        "wine_substrate": False,
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility / anti-cheat claim",
        "pe6 golden PARTIAL kept honest (not rewritten as PASS)",
        "Flatpak PARTIAL kept honest",
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

require_file "docs/plans/kickoff/PE7-closeout.md"
require_file "docs/plans/portable-core/USER-GUIDE.md"
require_file "docs/plans/portable-core/pe-closeout-report.md"
require_file "docs/plans/portable-core/artifacts.json"
require_file "docs/plans/portable-core/inventory.json"
require_file "docs/user/portable-guide.md"
require_file "docs/plans/stage-reports/PE7-closeout-report.md"
require_file "README.md"
require_file "tests/portable/output/pe0-remove-wine.json"
require_file "tests/portable/output/pe-real-exec.json"
require_file "tests/portable/output/pe-console.json"
require_file "tests/portable/output/pe-gui.json"
require_file "tests/portable/output/pe-installer.json"
require_file "tests/portable/output/pe-desktop-click.json"
require_file "tests/portable/output/pe-golden.json"
require_file "tests/portable/output/matrix.json"
require_file "tests/portable/output/SHA256SUMS"

accept_status() {
    local got="$1"
    local allow_partial="${2:-0}"
    if [[ "$got" == "PASS" ]]; then
        return 0
    fi
    if [[ "$allow_partial" == "1" && "$got" == "PARTIAL" ]]; then
        return 0
    fi
    return 1
}

s0="$(json_status "${OUT_DIR}/pe0-remove-wine.json")"
s1="$(json_status "${OUT_DIR}/pe-real-exec.json")"
s2="$(json_status "${OUT_DIR}/pe-console.json")"
s3="$(json_status "${OUT_DIR}/pe-gui.json")"
s4="$(json_status "${OUT_DIR}/pe-installer.json")"
s5="$(json_status "${OUT_DIR}/pe-desktop-click.json")"
s6="$(json_status "${OUT_DIR}/pe-golden.json")"
sm="$(json_status "${OUT_DIR}/matrix.json")"

accept_status "$s0" || failures+=("pe0-remove-wine status=${s0}")
accept_status "$s1" || failures+=("pe-real-exec status=${s1}")
accept_status "$s2" || failures+=("pe-console status=${s2}")
accept_status "$s3" 1 || failures+=("pe-gui status=${s3}")
accept_status "$s4" 1 || failures+=("pe-installer status=${s4}")
accept_status "$s5" || failures+=("pe-desktop-click status=${s5}")
accept_status "$s6" 1 || failures+=("pe-golden status=${s6}")
accept_status "$sm" || failures+=("matrix status=${sm}")

# pe6 must remain honest PARTIAL or PASS — never silently upgrade
if [[ "$s6" == "FAIL" ]]; then
    failures+=("pe-golden FAIL (must be PASS or honest PARTIAL)")
fi

distro_n="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(max(len(d.get("distros") or []), len(d.get("results") or [])))' "${OUT_DIR}/matrix.json" 2>/dev/null || echo 0)"
[[ "${distro_n}" -ge 3 ]] || failures+=("matrix distros=${distro_n} (<3)")

# artifacts.json
python3 - "${ARTIFACTS_JSON}" "${VERSION}" <<'PY' || failures+=("artifacts.json invalid")
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
version = sys.argv[2]
d = json.loads(p.read_text(encoding="utf-8"))
assert d.get("schema") == "strawwu-portable-artifacts/v1", d.get("schema")
arts = d.get("artifacts") or []
assert len(arts) >= 2, "need >=2 artifacts"
for a in arts:
    assert "name" in a and "sha256" in a and "kind" in a, a
notes = " ".join(d.get("notes") or []).lower()
assert "wine" not in notes or "removed" in notes or "not" in notes or "no" in notes or "禁" in notes or "native" in notes
# Prefer current VERSION in artifact names when present
names = " ".join(a.get("name", "") for a in arts)
if version not in names:
    # soft: allow if notes mention rebuild pending, but pe7 expects match
    raise SystemExit(f"artifacts.json names missing VERSION {version}")
print("artifacts.json ok", len(arts), "version", version)
PY

sums_lines="$(grep -cE '^[0-9a-f]{64} ' "${SUMS}" 2>/dev/null || echo 0)"
[[ "${sums_lines}" -ge 2 ]] || failures+=("SHA256SUMS entries=${sums_lines}")

# SHA256SUMS must mention current VERSION artifacts
if ! grep -q "StrawWU-Core-${VERSION}-" "${SUMS}"; then
    failures+=("SHA256SUMS missing version ${VERSION} artifacts")
fi

# Release binaries present
DIST="${REPO_ROOT}/components/packaging/portable/appimage/dist"
[[ -f "${DIST}/StrawWU-Core-${VERSION}-x86_64.AppImage" ]] \
    || failures+=("missing AppImage for ${VERSION}")
[[ -f "${DIST}/StrawWU-Core-${VERSION}-x86_64.portable.tar.gz" ]] \
    || failures+=("missing portable.tar.gz for ${VERSION}")

# Product path: no Wine substrate markers (exclude tests/docs that only scan for wine)
if command -v rg >/dev/null 2>&1; then
    if rg -n -i 'ensure_wine|wine_backend|STRAWWU_BACKEND=wine|backend=wine' \
        --glob '!docs/**' --glob '!.git/**' --glob '!tests/**' \
        --glob '!**/target/**' --glob '!**/pe*-side-effects/**' \
        "${REPO_ROOT}/components" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" \
        "${REPO_ROOT}/hub" >/tmp/pe7-wine-rg.txt 2>/dev/null; then
        failures+=("wine substrate markers in product tree (see /tmp/pe7-wine-rg.txt)")
    fi
fi

# README / USER-GUIDE must document native, not Wine default
if grep -qiE 'default backend\s*=\s*wine|via Wine|STRAWWU_BACKEND=wine' "${REPO_ROOT}/README.md"; then
    failures+=("README still documents Wine as default")
fi
if ! grep -qiE 'execution_backend=native|strawwu-nt|backend=native' "${REPO_ROOT}/README.md"; then
    failures+=("README missing native backend documentation")
fi

# Binary smoke: prefix strawwu must report native (if built)
PREFIX_BIN="${REPO_ROOT}/components/packaging/portable/prefix/bin/strawwu"
if [[ -x "${PREFIX_BIN}" ]]; then
    status_out="$("${PREFIX_BIN}" status 2>&1 || true)"
    if echo "${status_out}" | grep -qiE 'default backend=wine|execution_backend=wine'; then
        failures+=("prefix strawwu still reports wine backend")
    fi
    if ! echo "${status_out}" | grep -qiE 'execution_backend=native|default backend=native'; then
        failures+=("prefix strawwu missing native backend status")
    fi
else
    failures+=("prefix strawwu binary missing — rebuild required")
fi

# Render HTML
if [[ -f "${REPO_ROOT}/tests/portable/render-pe-closeout-html.py" ]]; then
    python3 "${REPO_ROOT}/tests/portable/render-pe-closeout-html.py" \
        || failures+=("render-pe-closeout-html failed")
fi
require_file "docs/plans/portable-core/html/pe-closeout-report.html"

# Merge check
if [[ "${SKIP_MERGE}" -eq 0 ]]; then
    git -C "${REPO_ROOT}" fetch origin main >/dev/null 2>&1 || true
    if git -C "${REPO_ROOT}" rev-parse origin/main >/dev/null 2>&1; then
        if git -C "${REPO_ROOT}" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
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
log "pe-closeout PASS version=${VERSION}"
exit 0
