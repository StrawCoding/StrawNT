"""StrawWU semver policy: MAJOR=0 pre-release; MAJOR>=1 only with .official-release-authorized."""
from __future__ import annotations

import re
from pathlib import Path

PRE_RELEASE = re.compile(r"^0\.\d+\.\d+\.\d+$")
OFFICIAL = re.compile(r"^1\.\d+\.\d+\.\d+$")


def official_release_authorized(repo_root: Path) -> bool:
    return (repo_root / ".official-release-authorized").is_file()


def check_version_policy(repo_root: Path, version: str) -> tuple[bool, str]:
    version = version.strip()
    if PRE_RELEASE.match(version):
        return True, f"VERSION MAJOR=0 policy: {version}"
    if OFFICIAL.match(version) and official_release_authorized(repo_root):
        return True, f"VERSION official release authorized: {version}"
    if OFFICIAL.match(version):
        return False, (
            f"VERSION semver MAJOR>=1 requires .official-release-authorized: {version}"
        )
    return False, f"VERSION semver MAJOR must be 0 before 1.0.0: {version}"
