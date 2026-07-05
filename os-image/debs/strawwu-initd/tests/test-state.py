#!/usr/bin/env python3
"""Unit tests for strawwu-initd state library."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "usr" / "lib" / "strawwu-initd"
sys.path.insert(0, str(LIB))

from state import (  # noqa: E402
    default_state,
    init_state,
    load_state,
    repair_state,
    save_state,
    set_nested,
    validate_state,
)


class StateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.state_file = Path(self.tmp.name) / "state.json"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_default_state_valid(self) -> None:
        data = default_state()
        self.assertEqual([], validate_state(data))
        self.assertEqual("1.0", data["schema_version"])
        self.assertTrue(data["flags"]["firstboot_required"])

    def test_init_and_load(self) -> None:
        data = init_state(path=self.state_file)
        self.assertTrue(self.state_file.exists())
        loaded = load_state(self.state_file)
        self.assertEqual(data["schema_version"], loaded["schema_version"])
        self.assertEqual("pending", loaded["lifecycle"]["firstboot"])

    def test_set_lifecycle_updates_timestamp(self) -> None:
        init_state(path=self.state_file)
        data = load_state(self.state_file)
        set_nested(data, "lifecycle.firstboot", "done")
        save_state(data, self.state_file)
        loaded = load_state(self.state_file)
        self.assertEqual("done", loaded["lifecycle"]["firstboot"])
        self.assertIn("firstboot_at", loaded["timestamps"])

    def test_set_rejects_invalid_lifecycle(self) -> None:
        data = default_state()
        with self.assertRaises(ValueError):
            set_nested(data, "lifecycle.install", "bogus")

    def test_repair_corrupt_json(self) -> None:
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text("{not json", encoding="utf-8")
        repaired = repair_state(self.state_file)
        self.assertEqual([], validate_state(repaired))
        json.loads(self.state_file.read_text(encoding="utf-8"))

    def test_repair_valid_state_noop(self) -> None:
        init_state(path=self.state_file)
        before = load_state(self.state_file)
        after = repair_state(self.state_file)
        self.assertEqual(before["meta"]["install_id"], after["meta"]["install_id"])


if __name__ == "__main__":
    unittest.main()
