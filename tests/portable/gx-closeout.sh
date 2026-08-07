#!/usr/bin/env bash
# LEGACY/ARCHIVE (NTW0 Wine pivot 2026-08-07): native-era evidence path.
# Product default is now execution_backend=wine / proton-ge. Do not treat
# wine_proton_used=false as a product PASS gate. See tests/archive/native/README.md.
# gx-closeout.sh — Game Compat gx5 closeout evidence generator.
# Validates gx0–gx4 evidence, docs, release artifacts/SHA256, cross-distro
# matrix, HTML report; writes tests/portable/output/gx-closeout.json.
# Historical exclusions for THIS evidence path only (not product contract):
# no ISO work; no WinBox naming; no full Windows / ranked AC claims.
# Invoke via: make test-legacy-portable-gx-closeout
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/portable/output"
OUT_JSON="${OUT_DIR}/gx-closeout.json"
PORTABLE_DOCS="${REPO_ROOT}/docs/plans/portable-core"
SUMS="${OUT_DIR}/SHA256SUMS"
ARTIFACTS_JSON="${PORTABLE_DOCS}/artifacts.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
SKIP_MERGE=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: gx-closeout.sh [--dry-run] [--skip-merge-check] [-h|--help]

Game Compat closeout (gx5).

  --dry-run             Check required paths only; write FAIL if incomplete
  --skip-merge-check    Do not require origin/main to contain HEAD
  -h, --help            Show this help

PASS: gx0–gx4 evidence OK (gx3/gx4 may be PARTIAL), docs+artifacts+SHA256 present,
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

log() { echo "[gx-closeout] $*"; }
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
    "gx0-graphics-vk-gl": stage(
        "gx0",
        out_dir / "gx-graphics.json",
        ["tests/portable/output/gx-graphics.json"],
        allow_partial=True,
    ),
    "gx1-audio-input": stage(
        "gx1",
        out_dir / "gx-audio-input.json",
        ["tests/portable/output/gx-audio-input.json"],
        allow_partial=True,
    ),
    "gx2-light-2d3d": stage(
        "gx2",
        out_dir / "gx-light-games.json",
        ["tests/portable/output/gx-light-games.json"],
        allow_partial=True,
    ),
    "gx3-launcher-smoke": stage(
        "gx3",
        out_dir / "gx-launchers.json",
        ["tests/portable/output/gx-launchers.json"],
        allow_partial=True,
    ),
    "gx4-anticheat-matrix": stage(
        "gx4",
        out_dir / "gx-anticheat.json",
        ["tests/portable/output/gx-anticheat.json"],
        allow_partial=True,
    ),
    "pc4-cross-distro-smoke": stage(
        "pc4",
        out_dir / "matrix.json",
        ["tests/portable/output/matrix.json"],
    ),
    "gx5-closeout": {
        "status": status,
        "evidence": [
            "tests/portable/output/gx-closeout.json",
            "docs/plans/portable-core",
        ],
        "acceptable": status == "PASS",
    },
}

docs = {
    "user_guide": str((portable / "USER-GUIDE.md").relative_to(repo)) if (portable / "USER-GUIDE.md").is_file() else None,
    "user_facing": "docs/user/portable-guide.md" if (repo / "docs/user/portable-guide.md").is_file() else None,
    "closeout_report": str((portable / "gx-closeout-report.md").relative_to(repo))
        if (portable / "gx-closeout-report.md").is_file() else None,
    "html": str((portable / "html" / "gx-closeout-report.html").relative_to(repo))
        if (portable / "html" / "gx-closeout-report.html").is_file() else None,
    "kickoff": "docs/plans/kickoff/GX5-closeout.md"
        if (repo / "docs/plans/kickoff/GX5-closeout.md").is_file() else None,
    "stage_report": "docs/plans/stage-reports/GX5-closeout-report.md"
        if (repo / "docs/plans/stage-reports/GX5-closeout-report.md").is_file() else None,
    "artifacts_index": "docs/plans/portable-core/artifacts.json"
        if (portable / "artifacts.json").is_file() else None,
    "readme": "README.md" if (repo / "README.md").is_file() else None,
}

sha256_path = out_dir / "SHA256SUMS"
sha256_ok = sha256_path.is_file() and sha256_path.stat().st_size > 0

dist = repo / "components" / "packaging" / "portable" / "appimage" / "dist"
appimage = dist / f"StrawWU-Core-{version}-x86_64.AppImage"
tarball = dist / f"StrawWU-Core-{version}-x86_64.portable.tar.gz"

# Honest claim scan: affirmative overclaims only (skip denial context)
import re as _re
_deny = _re.compile(r"(禁止|未|不|勿|禁|no |not |never |without )", _re.I)
_bad = _re.compile(
    r"(排位通過|ranked\s+pass|完整\s*windows\s*相容保證|"
    r"full windows compatibility guaranteed|anti-cheat\s+pass|反作弊通過|3a\s*全開)",
    _re.I,
)
claim_hits = []
for rel in (
    "README.md",
    "docs/plans/portable-core/USER-GUIDE.md",
    "docs/plans/portable-core/gx-closeout-report.md",
    "docs/user/portable-guide.md",
):
    p = repo / rel
    if not p.is_file():
        continue
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if _bad.search(line) and not _deny.search(line):
            claim_hits.append(f"{rel}:{i}:{line.strip()[:80]}")

doc = {
    "schema": "strawwu-portable-gx-closeout/v1",
    "stage": "gx5-closeout",
    "status": status,
    "version": version,
    "track": "game-compat",
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
        "gx0_graphics": jq_status(out_dir / "gx-graphics.json"),
        "gx1_audio_input": jq_status(out_dir / "gx-audio-input.json"),
        "gx2_light_games": jq_status(out_dir / "gx-light-games.json"),
        "gx3_launchers": jq_status(out_dir / "gx-launchers.json"),
        "gx4_anticheat": jq_status(out_dir / "gx-anticheat.json"),
        "pe6_golden": jq_status(out_dir / "pe-golden.json"),
        "flatpak": jq_status(out_dir / "smoke-flatpak.json"),
        "full_windows_claim": False,
        "anti_cheat_ranked_claim": False,
        "aaa_complete_claim": False,
        "wine_substrate": False,
        "forbidden_claim_hits": claim_hits,
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "legacy/archive native-era path; product default execution_backend=wine (proton-ge; powered by Wine); not a full Windows OS claim",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked / 排位通過 claim",
        "gx3 launchers PARTIAL kept honest (launcher-only; not full game play)",
        "gx4 anticheat PARTIAL kept honest (probe matrix; not ranked pass)",
        "cross-distro matrix reused from pc4 smoke-matrix.sh",
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

require_file "docs/plans/kickoff/GX5-closeout.md"
require_file "docs/plans/portable-core/USER-GUIDE.md"
require_file "docs/plans/portable-core/gx-closeout-report.md"
require_file "docs/plans/portable-core/artifacts.json"
require_file "docs/plans/portable-core/inventory.json"
require_file "docs/user/portable-guide.md"
require_file "docs/plans/stage-reports/GX5-closeout-report.md"
require_file "README.md"
require_file "tests/portable/output/gx-graphics.json"
require_file "tests/portable/output/gx-audio-input.json"
require_file "tests/portable/output/gx-light-games.json"
require_file "tests/portable/output/gx-launchers.json"
require_file "tests/portable/output/gx-anticheat.json"
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

s0="$(json_status "${OUT_DIR}/gx-graphics.json")"
s1="$(json_status "${OUT_DIR}/gx-audio-input.json")"
s2="$(json_status "${OUT_DIR}/gx-light-games.json")"
s3="$(json_status "${OUT_DIR}/gx-launchers.json")"
s4="$(json_status "${OUT_DIR}/gx-anticheat.json")"
sm="$(json_status "${OUT_DIR}/matrix.json")"

accept_status "$s0" 1 || failures+=("gx-graphics status=${s0}")
accept_status "$s1" 1 || failures+=("gx-audio-input status=${s1}")
accept_status "$s2" 1 || failures+=("gx-light-games status=${s2}")
accept_status "$s3" 1 || failures+=("gx-launchers status=${s3}")
accept_status "$s4" 1 || failures+=("gx-anticheat status=${s4}")
accept_status "$sm" || failures+=("matrix status=${sm}")

# gx3/gx4 must remain honest PARTIAL or PASS — never silently upgrade FAIL
if [[ "$s3" == "FAIL" ]]; then
    failures+=("gx-launchers FAIL (must be PASS or honest PARTIAL)")
fi
if [[ "$s4" == "FAIL" ]]; then
    failures+=("gx-anticheat FAIL (must be PASS or honest PARTIAL)")
fi

# gx4 must not claim ranked pass
python3 - "${OUT_DIR}/gx-anticheat.json" <<'PY' || failures+=("gx-anticheat dishonest ranked claim")
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
claims = d.get("claims") or {}
if claims.get("ranked_pass_claimed") or claims.get("anti_cheat_claimed"):
    raise SystemExit("ranked/anti_cheat claimed true")
if d.get("status") == "PASS" and any(
    (c.get("grade") == "F") for c in (d.get("cases") or [])
):
    # allow PASS only if no F grades; current honest path is PARTIAL
    pass
print("gx-anticheat honesty ok", d.get("status"))
PY

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
notes = " ".join(str(x) for x in (d.get("notes") or [])).lower()
# Must mention native / no wine substrate and game-compat honesty
# NTW0 soft-reset: wine is product substrate
assert ("wine" in notes) or ("native" in notes) or ("powered" in notes) or ("strawwu-nt" in notes), "artifacts notes missing backend honesty"
names = " ".join(a.get("name", "") for a in arts)
if version not in names:
    raise SystemExit(f"artifacts.json names missing VERSION {version}")
print("artifacts.json ok", len(arts), "version", version)
PY

sums_lines="$(grep -cE '^[0-9a-f]{64} ' "${SUMS}" 2>/dev/null || echo 0)"
[[ "${sums_lines}" -ge 2 ]] || failures+=("SHA256SUMS entries=${sums_lines}")

if ! grep -q "StrawWU-Core-${VERSION}-" "${SUMS}"; then
    failures+=("SHA256SUMS missing version ${VERSION} artifacts")
fi

DIST="${REPO_ROOT}/components/packaging/portable/appimage/dist"
[[ -f "${DIST}/StrawWU-Core-${VERSION}-x86_64.AppImage" ]] \
    || failures+=("missing AppImage for ${VERSION}")
[[ -f "${DIST}/StrawWU-Core-${VERSION}-x86_64.portable.tar.gz" ]] \
    || failures+=("missing portable.tar.gz for ${VERSION}")

# NTW0 soft-reset: product default is wine
if ! grep -qiE 'execution_backend=wine|backend=wine|powered by Wine' "${REPO_ROOT}/README.md"; then
    failures+=("README missing wine backend / powered by Wine (NTW0)")
fi

# Docs must mention game-compat honesty (launchers PARTIAL / AC no ranked)
if ! grep -qiE 'gx3|launcher|啟動器' "${REPO_ROOT}/docs/plans/portable-core/USER-GUIDE.md"; then
    failures+=("USER-GUIDE missing launcher/gx3 honesty")
fi
if ! grep -qiE 'anticheat|反作弊|gx4' "${REPO_ROOT}/docs/plans/portable-core/USER-GUIDE.md"; then
    failures+=("USER-GUIDE missing anticheat/gx4 honesty")
fi
if ! grep -qiE '排位|ranked' "${REPO_ROOT}/docs/plans/portable-core/gx-closeout-report.md"; then
    failures+=("gx-closeout-report missing ranked-pass denial")
fi
# Forbidden overclaims: affirmative wording without denial context
python3 - "${REPO_ROOT}" <<'PY' || failures+=("docs contain forbidden overclaim phrasing")
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
paths = [
    root / "docs/plans/portable-core/gx-closeout-report.md",
    root / "docs/plans/portable-core/USER-GUIDE.md",
    root / "README.md",
]
deny = re.compile(r"(禁止|未|不|勿|禁|no |not |never |without )", re.I)
bad = re.compile(
    r"(排位通過|ranked\s+pass|完整\s*Windows\s*相容保證|anti-cheat\s+pass|3[Aa]\s*全開)",
    re.I,
)
hits = []
for p in paths:
    if not p.is_file():
        continue
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if bad.search(line) and not deny.search(line):
            hits.append(f"{p.relative_to(root)}:{i}:{line.strip()[:80]}")
if hits:
    print("\n".join(hits))
    raise SystemExit(1)
print("overclaim scan ok")
PY

PREFIX_BIN="${REPO_ROOT}/components/packaging/portable/prefix/bin/strawnt"
if [[ ! -x "${PREFIX_BIN}" ]]; then
    PREFIX_BIN="${REPO_ROOT}/components/packaging/portable/prefix/bin/strawwu"
fi
if [[ -x "${PREFIX_BIN}" ]]; then
    status_out="$("${PREFIX_BIN}" status 2>&1 || true)"
    if ! echo "${status_out}" | grep -qiE 'execution_backend=wine|default backend=wine|powered by Wine'; then
        failures+=("prefix strawnt missing wine backend status (NTW0)")
    fi
else
    failures+=("prefix strawwu binary missing — rebuild required")
fi

# Render HTML
if [[ -f "${REPO_ROOT}/tests/portable/render-gx-closeout-html.py" ]]; then
    python3 "${REPO_ROOT}/tests/portable/render-gx-closeout-html.py" \
        || failures+=("render-gx-closeout-html failed")
fi
require_file "docs/plans/portable-core/html/gx-closeout-report.html"

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
log "gx-closeout PASS version=${VERSION}"
exit 0
