#!/usr/bin/env bash
# Verify all post_mvp_locked_sequence stages are PASS in Hermes state.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERMES="${HERMES_HOME:-/root/.hermes}"
STATE="${HERMES}/logs/task-workers/strawwu/state.json"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"
OUT="${ROOT}/docs/plans/baselines/post-mvp-status.json"

if [[ ! -f "${STATE}" ]]; then
  echo "FAIL: missing state.json: ${STATE}" >&2
  exit 1
fi

python3 - "${CFG}" "${STATE}" "${OUT}" <<'PY'
import json, pathlib, sys
cfg_path, state_path, out_path = map(pathlib.Path, sys.argv[1:4])
cfg = json.loads(cfg_path.read_text())
state = json.loads(state_path.read_text())
seq = cfg.get("post_mvp_locked_sequence") or []
stages = state.get("stages") or {}

rows = []
fail = 0
for sid in seq:
    st = (stages.get(sid) or {}).get("status", "PENDING")
    ok = st == "PASS"
    if not ok:
        fail += 1
    rows.append({"id": sid, "status": st, "pass": ok})

report = {
    "generated_at": __import__("datetime").datetime.now().isoformat(),
    "target": "0.9.0.0-engineering",
    "total": len(seq),
    "passed": sum(1 for r in rows if r["pass"]),
    "failed": fail,
    "all_pass": fail == 0,
    "stages": rows,
}

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

print(f"Post-MVP status: {report['passed']}/{report['total']} PASS")
for r in rows:
    mark = "OK" if r["pass"] else "FAIL"
    print(f"  [{mark}] {r['id']}: {r['status']}")

if fail:
    raise SystemExit(1)
print("ALL POST-MVP STAGES PASS")
PY

echo "post-mvp-status.json written: ${OUT}"
