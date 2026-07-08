#!/usr/bin/env python3
"""Estimate boot-to-Plymouth seconds from an existing QEMU serial log + boot elapsed."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def estimate(serial_path: Path, boot_result_path: Path | None, marker: str) -> dict:
    text = serial_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    marker_idx = next((i for i, line in enumerate(lines) if marker in line), None)
    total_sec = None
    if boot_result_path and boot_result_path.is_file():
        boot = json.loads(boot_result_path.read_text(encoding="utf-8"))
        bios = boot.get("bios") or {}
        total_sec = bios.get("elapsed_sec")

    if marker_idx is None:
        return {"status": "FAIL", "plymouth_sec": None, "detail": f"marker {marker!r} not in serial log"}

    if total_sec and len(lines) > 1:
        ratio = marker_idx / max(len(lines) - 1, 1)
        est = max(1, round(float(total_sec) * ratio))
        return {
            "status": "PASS",
            "plymouth_sec": est,
            "detail": f"estimated {est}s from line ratio ({marker_idx}/{len(lines)}) × {total_sec}s boot",
            "method": "serial-line-ratio",
        }

    return {
        "status": "PASS",
        "plymouth_sec": None,
        "detail": "marker found but no boot elapsed for ratio estimate",
        "method": "marker-only",
    }


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: estimate-from-serial.py <serial.log> [boot-result.json] [marker]", file=sys.stderr)
        return 2
    serial = Path(argv[1])
    boot = Path(argv[2]) if len(argv) > 2 and argv[2].endswith(".json") else None
    marker = argv[3] if len(argv) > 3 else (argv[2] if len(argv) > 2 and not argv[2].endswith(".json") else "plymouth-start.service")
    if not serial.is_file():
        print(f"FAIL: missing {serial}", file=sys.stderr)
        return 1
    out = estimate(serial, boot, marker)
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0 if out.get("plymouth_sec") is not None else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
