#!/usr/bin/env python3
"""PERF2 boot-time regression gate — compare measurement vs baseline + budget."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def effective_threshold(baseline: dict[str, Any]) -> tuple[float | None, str]:
    budgets = baseline.get("budgets", {})
    hard_max = budgets.get("live_boot_to_plymouth_max_sec")
    ratio = budgets.get("regression_ratio_max", 1.15)
    base = baseline.get("baseline", {}).get("plymouth_sec")

    if base is not None:
        regressed = float(base) * float(ratio)
        if hard_max is not None:
            limit = min(regressed, float(hard_max))
            return limit, f"min(baseline {base}s × {ratio}, budget {hard_max}s)"
        return regressed, f"baseline {base}s × {ratio}"

    if hard_max is not None:
        return float(hard_max), f"budget cap {hard_max}s (no baseline yet)"
    return None, "no threshold configured"


def extract_plymouth_sec(measurement: dict[str, Any]) -> float | None:
    if measurement.get("plymouth_sec") is not None:
        return float(measurement["plymouth_sec"])
    inner = measurement.get("measurement") or {}
    if inner.get("plymouth_sec") is not None:
        return float(inner["plymouth_sec"])
    return None


def check(
    baseline_path: Path,
    measurement_path: Path | None,
    gate_mode: str,
) -> dict[str, Any]:
    baseline = load_json(baseline_path)
    plymouth_sec: float | None = None
    measurement_status = "missing"

    if measurement_path and measurement_path.is_file():
        measurement = load_json(measurement_path)
        plymouth_sec = extract_plymouth_sec(measurement)
        measurement_status = measurement.get("status") or (
            "pass" if plymouth_sec is not None else "missing"
        )

    threshold, threshold_note = effective_threshold(baseline)
    result = "skipped"
    detail = "no measurement artifact"

    if plymouth_sec is None:
        if gate_mode == "strict":
            result = "fail"
            detail = "strict gate requires boot-time measurement"
        else:
            result = "advisory"
            detail = "no measurement — advisory skip"
    elif threshold is None:
        result = "pass"
        detail = f"measured {plymouth_sec}s (no threshold)"
    elif plymouth_sec <= threshold:
        result = "pass"
        detail = f"measured {plymouth_sec}s ≤ {threshold:.1f}s ({threshold_note})"
    elif gate_mode == "strict":
        result = "fail"
        detail = f"measured {plymouth_sec}s > {threshold:.1f}s ({threshold_note})"
    else:
        result = "advisory"
        detail = f"measured {plymouth_sec}s > {threshold:.1f}s ({threshold_note}) — advisory"

    return {
        "gate_mode": gate_mode,
        "result": result,
        "plymouth_sec": plymouth_sec,
        "threshold_sec": threshold,
        "threshold_note": threshold_note,
        "detail": detail,
        "measurement_status": measurement_status,
    }


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: check-boot-regression.py <baseline.json> [measurement.json] [gate_mode]", file=sys.stderr)
        return 2

    baseline_path = Path(argv[1])
    gate_mode = "advisory"
    measurement_path: Path | None = None

    for arg in argv[2:]:
        if arg in ("advisory", "strict"):
            gate_mode = arg
        elif measurement_path is None:
            measurement_path = Path(arg)

    if not baseline_path.is_file():
        print(f"FAIL: baseline missing {baseline_path}", file=sys.stderr)
        return 1

    outcome = check(baseline_path, measurement_path, gate_mode)
    print(json.dumps(outcome, indent=2, ensure_ascii=False))

    if outcome["result"] == "fail":
        print(f"FAIL: {outcome['detail']}", file=sys.stderr)
        return 1
    print(f"PASS: {outcome['detail']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
