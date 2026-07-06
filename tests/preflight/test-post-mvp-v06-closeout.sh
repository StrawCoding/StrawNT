#!/usr/bin/env bash
# v0.6 post-mvp closeout: stages 1-5 must be PASS in Hermes state.
set -euo pipefail

HERMES="${HERMES_HOME:-/root/.hermes}"
STATE="${HERMES}/logs/task-workers/strawwu/state.json"
CFG="${HERMES}/config/task-workers/projects/strawwu.json"

python3 - "${CFG}" "${STATE}" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
state = json.loads(pathlib.Path(sys.argv[2]).read_text())
v06 = [
    "post-d1-strawwu-drivers",
    "post-hw-t1-live-usb",
    "post-hw-t2-installed",
    "post-hw4-peripherals",
    "post-ddp-rootfs",
    "post-q3-mfp-smoke",
    "post-i2-calamares-luks",
    "post-d7-software-sources",
    "post-ux-theme-curation",
]
st = state.get("stages") or {}
fail = 0
for sid in v06:
    ok = (st.get(sid) or {}).get("status") == "PASS"
    print(f"  [{'OK' if ok else 'FAIL'}] {sid}")
    if not ok:
        fail += 1
if fail:
    raise SystemExit(1)
print("v0.6 post-mvp stages PASS")
PY
