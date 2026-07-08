#!/usr/bin/env python3
"""Compute POST-HW5 stable_summary for T1+T2 real-hardware matrix entries."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

REAL_ENVIRONMENTS = frozenset(
    {"physical-live", "physical-installed", "installed-e2e"}
)
EXCLUDED_ENVIRONMENTS = frozenset({"qemu-proxy", "qemu", "fixture"})

T1_REQUIRED = ("live_boot", "desktop", "gpu_driver", "wifi")
T2_INSTALLED_REQUIRED = ("installed_boot", "suspend", "hidpi")
T2_PERIPHERAL_REQUIRED = ("peripherals",)


def _test_value(tests: dict[str, Any], key: str) -> str:
    value = tests.get(key)
    if value is None:
        return "SKIP"
    return str(value)


def machine_stable(machine: dict[str, Any]) -> bool | None:
    """Return True/False for stable, or None if machine is out of HW5 scope."""
    tier = machine.get("tier", "")
    environment = machine.get("environment", "")

    if environment in EXCLUDED_ENVIRONMENTS:
        return None
    if tier not in ("T1", "T2"):
        return None
    if environment and environment not in REAL_ENVIRONMENTS:
        # Unknown env on T1/T2 — only count explicit real-hardware sessions.
        return None

    overall = machine.get("overall") or machine.get("status")
    if overall in ("PASS", "FAIL"):
        return overall == "PASS"

    tests = machine.get("tests") or {}
    phase = machine.get("phase", "")

    if tier == "T1":
        required = T1_REQUIRED
    elif phase == "peripheral-smoke":
        required = T2_PERIPHERAL_REQUIRED
    else:
        required = T2_INSTALLED_REQUIRED

    for key in required:
        value = _test_value(tests, key)
        if value == "FAIL":
            return False
        if value in ("SKIP", "PARTIAL") and key in required[:2]:
            # Core boot/desktop/installed paths must not be skipped for stable.
            if key in ("live_boot", "desktop", "installed_boot"):
                return False
    return True


def compute_stable_summary(data: dict[str, Any]) -> dict[str, Any]:
    machines = data.get("machines") or data.get("entries") or []
    scoped: list[dict[str, Any]] = []
    stable_ids: list[str] = []
    unstable_ids: list[str] = []

    for machine in machines:
        stable = machine_stable(machine)
        if stable is None:
            continue
        scoped.append(machine)
        mid = machine.get("machine_id", "?")
        if stable:
            stable_ids.append(mid)
        else:
            unstable_ids.append(mid)

    total = len(scoped)
    stable_count = len(stable_ids)
    rate = (stable_count / total) if total else 0.0

    t1 = [m for m in scoped if m.get("tier") == "T1"]
    t2 = [m for m in scoped if m.get("tier") == "T2"]

    return {
        "scope": "T1+T2 real-hardware (physical-live, physical-installed, installed-e2e)",
        "minimum_rate": 0.8,
        "stable_rate": round(rate, 4),
        "stable_count": stable_count,
        "total": total,
        "t1_count": len(t1),
        "t2_count": len(t2),
        "stable_machine_ids": stable_ids,
        "unstable_machine_ids": unstable_ids,
        "gate": "PASS" if total and rate >= 0.8 else "FAIL",
    }


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <hw-matrix-results.json>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    data = json.loads(path.read_text(encoding="utf-8"))
    summary = compute_stable_summary(data)
    data["stable_summary"] = summary
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    rate = summary["stable_rate"]
    print(
        f"PASS: stable_summary {rate:.0%} ({summary['stable_count']}/{summary['total']}) "
        f"T1={summary['t1_count']} T2={summary['t2_count']}"
        if summary["gate"] == "PASS"
        else f"FAIL: stable_rate {rate:.0%} < 80% ({summary['stable_count']}/{summary['total']})",
        flush=True,
    )
    return 0 if summary["gate"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
