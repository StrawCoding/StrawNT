"""Privacy filtering for StrawWU bug bundles (SEC2 / OBS2)."""

from __future__ import annotations

import re
from typing import Iterable

# Patterns that must never appear in exported bundles.
_SENSITIVE_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"(?i)\bpassword\b\s*[:=]\s*\S+"), "password=[REDACTED]"),
    (re.compile(r"(?i)\btoken\b\s*[:=]\s*\S+"), "token=[REDACTED]"),
    (re.compile(r"(?i)\bsecret\b\s*[:=]\s*\S+"), "secret=[REDACTED]"),
    (re.compile(r"-----BEGIN [A-Z ]+-----"), "[REDACTED_KEY_BLOCK]"),
    (re.compile(r"(?i)\bssid\b\s*[:=]\s*\S+"), "ssid=[REDACTED]"),
    (re.compile(r"(?i)\bpsk\b\s*[:=]\s*\S+"), "psk=[REDACTED]"),
    (re.compile(r"/home/[^/\s]+/[^\s]*"), "[REDACTED_HOME_PATH]"),
)


def redact_line(line: str) -> str:
    """Apply privacy redaction rules to a single log line."""
    result = line
    for pattern, replacement in _SENSITIVE_PATTERNS:
        result = pattern.sub(replacement, result)
    return result


def redact_text(text: str) -> str:
    """Redact an entire text blob line-by-line."""
    return "\n".join(redact_line(line) for line in text.splitlines())


def redact_lines(lines: Iterable[str]) -> list[str]:
    return [redact_line(line) for line in lines]
