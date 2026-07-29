#!/usr/bin/env bash
# nt5-youwan-closeout.sh — StrawNT youwan closeout evidence generator.
# Validates nt0–nt4 evidence, docs, release artifacts/SHA256, cross-distro
# matrix, HTML report; writes tests/strawnt/output/nt5-closeout.json.
# Forbidden: Wine/Proton substrate, WinBox naming, full Windows / ranked AC
# claims, ISO / StrawWU OS work.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/tests/strawnt/output"
OUT_JSON="${OUT_DIR}/nt5-closeout.json"
PORTABLE_OUT="${REPO_ROOT}/tests/portable/output"
PORTABLE_DOCS="${REPO_ROOT}/docs/plans/portable-core"
SUMS="${PORTABLE_OUT}/SHA256SUMS"
ARTIFACTS_JSON="${PORTABLE_DOCS}/artifacts.json"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION" 2>/dev/null || echo unknown)"
SKIP_MERGE=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: nt5-youwan-closeout.sh [--dry-run] [--skip-merge-check] [-h|--help]

StrawNT youwan closeout (nt5).

  --dry-run             Check required paths only; write FAIL if incomplete
  --skip-merge-check    Do not require origin/main to contain HEAD
  -h, --help            Show this help

PASS: nt0–nt4 evidence OK (nt3/nt4 may be PARTIAL), docs+artifacts+SHA256 present,
      matrix ≥3 distros PASS, origin/main contains tip (unless skipped),
      ${OUT_JSON} top-level status=PASS, product=StrawNT.
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

log() { echo "[nt5-closeout] $*"; }
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
portable_out = repo / "tests" / "portable" / "output"

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

def stage(path, evidence, allow_partial=False):
    st = jq_status(path)
    ok = st == "PASS" or (allow_partial and st == "PARTIAL")
    return {
        "status": st,
        "evidence": evidence,
        "acceptable": ok,
    }

stages = {
    "nt0-rebrand-disconnect": stage(
        out_dir / "nt0-rebrand.json",
        ["tests/strawnt/output/nt0-rebrand.json"],
    ),
    "nt1-real-graphics": stage(
        out_dir / "nt1-graphics.json",
        ["tests/strawnt/output/nt1-graphics.json"],
    ),
    "nt2-real-light-games": stage(
        out_dir / "nt2-light-games.json",
        ["tests/strawnt/output/nt2-light-games.json"],
    ),
    "nt3-real-launchers": stage(
        out_dir / "nt3-launchers.json",
        ["tests/strawnt/output/nt3-launchers.json"],
        allow_partial=True,
    ),
    "nt4-anticheat-honest": stage(
        out_dir / "nt4-anticheat.json",
        ["tests/strawnt/output/nt4-anticheat.json"],
        allow_partial=True,
    ),
    "pc4-cross-distro-smoke": stage(
        portable_out / "matrix.json",
        ["tests/portable/output/matrix.json"],
    ),
    "nt5-youwan-closeout": {
        "status": status,
        "evidence": [
            "tests/strawnt/output/nt5-closeout.json",
            "docs/plans/portable-core",
        ],
        "acceptable": status == "PASS",
    },
}

docs = {
    "user_guide": str((portable / "USER-GUIDE.md").relative_to(repo)) if (portable / "USER-GUIDE.md").is_file() else None,
    "user_facing": "docs/user/portable-guide.md" if (repo / "docs/user/portable-guide.md").is_file() else None,
    "closeout_report": str((portable / "nt5-closeout-report.md").relative_to(repo))
        if (portable / "nt5-closeout-report.md").is_file() else None,
    "html": str((portable / "html" / "nt5-closeout-report.html").relative_to(repo))
        if (portable / "html" / "nt5-closeout-report.html").is_file() else None,
    "kickoff": "docs/plans/kickoff/NT5-youwan-closeout.md"
        if (repo / "docs/plans/kickoff/NT5-youwan-closeout.md").is_file() else None,
    "stage_report": "docs/plans/stage-reports/NT5-youwan-closeout-report.md"
        if (repo / "docs/plans/stage-reports/NT5-youwan-closeout-report.md").is_file() else None,
    "artifacts_index": "docs/plans/portable-core/artifacts.json"
        if (portable / "artifacts.json").is_file() else None,
    "readme": "README.md" if (repo / "README.md").is_file() else None,
}

sha256_path = portable_out / "SHA256SUMS"
sha256_ok = sha256_path.is_file() and sha256_path.stat().st_size > 0

dist = repo / "components" / "packaging" / "portable" / "appimage" / "dist"
appimage = dist / f"StrawNT-{version}-x86_64.AppImage"
tarball = dist / f"StrawNT-{version}-x86_64.portable.tar.gz"

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
    "docs/plans/portable-core/nt5-closeout-report.md",
    "docs/user/portable-guide.md",
):
    p = repo / rel
    if not p.is_file():
        continue
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if _bad.search(line) and not _deny.search(line):
            claim_hits.append(f"{rel}:{i}:{line.strip()[:80]}")

doc = {
    "schema": "strawnt-nt5-youwan-closeout/v1",
    "stage": "nt5-youwan-closeout",
    "product": "StrawNT",
    "name": "StrawNT",
    "status": status,
    "version": version,
    "track": "youwan",
    "backend": "native",
    "execution_backend": "native",
    "cli": "strawnt",
    "github": "StrawCoding/StrawNT",
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
        "nt0_rebrand": jq_status(out_dir / "nt0-rebrand.json"),
        "nt1_graphics": jq_status(out_dir / "nt1-graphics.json"),
        "nt2_light_games": jq_status(out_dir / "nt2-light-games.json"),
        "nt3_launchers": jq_status(out_dir / "nt3-launchers.json"),
        "nt4_anticheat": jq_status(out_dir / "nt4-anticheat.json"),
        "cross_distro_matrix": jq_status(portable_out / "matrix.json"),
        "full_windows_claim": False,
        "anti_cheat_ranked_claim": False,
        "aaa_complete_claim": False,
        "wine_substrate": False,
        "forbidden_claim_hits": claim_hits,
    },
    "exclusions_honored": [
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop / StrawWU OS changes",
        "no Wine/Proton substrate; execution_backend=native",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked / 排位通過 claim",
        "nt3 launchers PARTIAL kept honest (launcher-only; not full game play)",
        "nt4 anticheat PARTIAL kept honest (probe matrix; not ranked pass)",
        "cross-distro matrix via smoke-matrix.sh (containers; not Live USB ISO)",
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

require_file "docs/plans/kickoff/NT5-youwan-closeout.md"
require_file "docs/plans/portable-core/USER-GUIDE.md"
require_file "docs/plans/portable-core/nt5-closeout-report.md"
require_file "docs/plans/portable-core/artifacts.json"
require_file "docs/user/portable-guide.md"
require_file "docs/plans/stage-reports/NT5-youwan-closeout-report.md"
require_file "README.md"
require_file "tests/strawnt/output/nt0-rebrand.json"
require_file "tests/strawnt/output/nt1-graphics.json"
require_file "tests/strawnt/output/nt2-light-games.json"
require_file "tests/strawnt/output/nt3-launchers.json"
require_file "tests/strawnt/output/nt4-anticheat.json"
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

s0="$(json_status "${OUT_DIR}/nt0-rebrand.json")"
s1="$(json_status "${OUT_DIR}/nt1-graphics.json")"
s2="$(json_status "${OUT_DIR}/nt2-light-games.json")"
s3="$(json_status "${OUT_DIR}/nt3-launchers.json")"
s4="$(json_status "${OUT_DIR}/nt4-anticheat.json")"
sm="$(json_status "${PORTABLE_OUT}/matrix.json")"

accept_status "$s0" || failures+=("nt0-rebrand status=${s0}")
accept_status "$s1" || failures+=("nt1-graphics status=${s1}")
accept_status "$s2" || failures+=("nt2-light-games status=${s2}")
accept_status "$s3" 1 || failures+=("nt3-launchers status=${s3}")
accept_status "$s4" 1 || failures+=("nt4-anticheat status=${s4}")
accept_status "$sm" || failures+=("matrix status=${sm}")

if [[ "$s3" == "FAIL" ]]; then
    failures+=("nt3-launchers FAIL (must be PASS or honest PARTIAL)")
fi
if [[ "$s4" == "FAIL" ]]; then
    failures+=("nt4-anticheat FAIL (must be PASS or honest PARTIAL)")
fi

# Product identity on prior stages
python3 - "${OUT_DIR}" <<'PY' || failures+=("prior stages missing product=StrawNT")
import json, sys
from pathlib import Path
d = Path(sys.argv[1])
for name in ("nt0-rebrand.json", "nt1-graphics.json", "nt2-light-games.json",
             "nt3-launchers.json", "nt4-anticheat.json"):
    p = d / name
    doc = json.loads(p.read_text(encoding="utf-8"))
    if doc.get("product") != "StrawNT" and doc.get("name") != "StrawNT":
        raise SystemExit(f"{name} missing product/name StrawNT")
print("prior product identity ok")
PY

# nt2 must be real binaries
python3 - "${OUT_DIR}/nt2-light-games.json" <<'PY' || failures+=("nt2 not real binaries")
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if not (d.get("real_binaries") is True or (d.get("claims") or {}).get("real_binaries") is True):
    raise SystemExit("real_binaries missing")
apps = d.get("apps") or d.get("results") or []
if any((a.get("mode") == "simulated") for a in apps):
    raise SystemExit("simulated app in nt2")
print("nt2 real ok")
PY

# nt4 must not claim ranked pass
python3 - "${OUT_DIR}/nt4-anticheat.json" <<'PY' || failures+=("nt4 dishonest ranked claim")
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
claims = d.get("claims") or {}
if claims.get("ranked_pass_claimed") or claims.get("anti_cheat_claimed"):
    raise SystemExit("ranked/anti_cheat claimed true")
print("nt4 honesty ok", d.get("status"))
PY

# matrix version should match current VERSION (warn soft if older reused — require PASS + ≥3)
distro_n="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(max(len(d.get("distros") or []), len(d.get("results") or [])))' "${PORTABLE_OUT}/matrix.json" 2>/dev/null || echo 0)"
[[ "${distro_n}" -ge 3 ]] || failures+=("matrix distros=${distro_n} (<3)")
matrix_ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "${PORTABLE_OUT}/matrix.json" 2>/dev/null || true)"
if [[ -n "${matrix_ver}" && "${matrix_ver}" != "${VERSION}" ]]; then
    failures+=("matrix version=${matrix_ver} != VERSION=${VERSION} (rerun smoke-matrix)")
fi

# artifacts.json
python3 - "${ARTIFACTS_JSON}" "${VERSION}" <<'PY' || failures+=("artifacts.json invalid")
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
version = sys.argv[2]
d = json.loads(p.read_text(encoding="utf-8"))
assert d.get("schema") in ("strawnt-artifacts/v1", "strawwu-portable-artifacts/v1"), d.get("schema")
assert d.get("product") in (None, "StrawNT") or d.get("schema") == "strawwu-portable-artifacts/v1"
arts = d.get("artifacts") or []
assert len(arts) >= 2, "need >=2 artifacts"
for a in arts:
    assert "name" in a and "sha256" in a and "kind" in a, a
notes = " ".join(str(x) for x in (d.get("notes") or [])).lower()
assert "native" in notes, "artifacts notes missing native"
assert "wine" not in notes or any(k in notes for k in ("removed", "not", "no", "禁", "forbid"))
names = " ".join(a.get("name", "") for a in arts)
if version not in names:
    raise SystemExit(f"artifacts.json names missing VERSION {version}")
if "StrawNT-" not in names:
    raise SystemExit("artifacts.json missing StrawNT- artifact names")
print("artifacts.json ok", len(arts), "version", version)
PY

sums_lines="$(grep -cE '^[0-9a-f]{64} ' "${SUMS}" 2>/dev/null || echo 0)"
[[ "${sums_lines}" -ge 2 ]] || failures+=("SHA256SUMS entries=${sums_lines}")

if ! grep -q "StrawNT-${VERSION}-" "${SUMS}"; then
    failures+=("SHA256SUMS missing version ${VERSION} artifacts")
fi

DIST="${REPO_ROOT}/components/packaging/portable/appimage/dist"
[[ -f "${DIST}/StrawNT-${VERSION}-x86_64.AppImage" ]] \
    || failures+=("missing AppImage for ${VERSION}")
[[ -f "${DIST}/StrawNT-${VERSION}-x86_64.portable.tar.gz" ]] \
    || failures+=("missing portable.tar.gz for ${VERSION}")

# Product path: no Wine substrate markers
if command -v rg >/dev/null 2>&1; then
    if rg -n -i 'ensure_wine|wine_backend|STRAWWU_BACKEND=wine|STRAWNT_BACKEND=wine|backend=wine' \
        --glob '!docs/**' --glob '!.git/**' --glob '!tests/**' \
        --glob '!**/target/**' --glob '!**/pe*-side-effects/**' \
        --glob '!**/gx*-side-effects/**' --glob '!**/nt*-side-effects/**' \
        "${REPO_ROOT}/components" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" \
        "${REPO_ROOT}/hub" >/tmp/nt5-wine-rg.txt 2>/dev/null; then
        failures+=("wine substrate markers in product tree (see /tmp/nt5-wine-rg.txt)")
    fi
fi

if grep -qiE 'default backend\s*=\s*wine|via Wine|STRAWWU_BACKEND=wine|STRAWNT_BACKEND=wine' "${REPO_ROOT}/README.md"; then
    failures+=("README still documents Wine as default")
fi
if ! grep -qiE 'execution_backend=native|backend=native' "${REPO_ROOT}/README.md"; then
    failures+=("README missing native backend documentation")
fi
if ! grep -q 'StrawNT' "${REPO_ROOT}/README.md"; then
    failures+=("README missing StrawNT")
fi

# Docs honesty
if ! grep -qiE 'nt3|launcher|啟動器' "${REPO_ROOT}/docs/plans/portable-core/USER-GUIDE.md"; then
    failures+=("USER-GUIDE missing launcher/nt3 honesty")
fi
if ! grep -qiE 'anticheat|反作弊|nt4' "${REPO_ROOT}/docs/plans/portable-core/USER-GUIDE.md"; then
    failures+=("USER-GUIDE missing anticheat/nt4 honesty")
fi
if ! grep -qiE '排位|ranked' "${REPO_ROOT}/docs/plans/portable-core/nt5-closeout-report.md"; then
    failures+=("nt5-closeout-report missing ranked-pass denial")
fi

python3 - "${REPO_ROOT}" <<'PY' || failures+=("docs contain forbidden overclaim phrasing")
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
paths = [
    root / "docs/plans/portable-core/nt5-closeout-report.md",
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
if [[ -x "${PREFIX_BIN}" ]]; then
    status_out="$("${PREFIX_BIN}" status 2>&1 || true)"
    if echo "${status_out}" | grep -qiE 'default backend=wine|execution_backend=wine'; then
        failures+=("prefix strawnt still reports wine backend")
    fi
    if ! echo "${status_out}" | grep -qiE 'execution_backend=native|default backend=native'; then
        failures+=("prefix strawnt missing native backend status")
    fi
    ver_out="$("${PREFIX_BIN}" --version 2>&1 || true)"
    if ! echo "${ver_out}" | grep -qi 'strawnt'; then
        failures+=("prefix --version missing strawnt")
    fi
else
    failures+=("prefix strawnt binary missing — rebuild required")
fi

# Render HTML
if [[ -f "${REPO_ROOT}/tests/strawnt/render-nt5-closeout-html.py" ]]; then
    python3 "${REPO_ROOT}/tests/strawnt/render-nt5-closeout-html.py" \
        || failures+=("render-nt5-closeout-html failed")
fi
require_file "docs/plans/portable-core/html/nt5-closeout-report.html"

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
log "nt5-closeout PASS version=${VERSION} product=StrawNT"
exit 0
