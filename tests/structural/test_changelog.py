"""Structural checks for CHANGELOG.md.

The release workflow (.github/workflows/release.yml) prepends a new section
to CHANGELOG.md after each tag release. These tests assert the seed file
remains well-formed so the awk-based insertion in that workflow keeps working.
"""

from __future__ import annotations

import re
from pathlib import Path


def test_changelog_exists(repo_root: Path) -> None:
    assert (repo_root / "CHANGELOG.md").is_file(), (
        "CHANGELOG.md is missing at the repository root. The release workflow "
        "expects this file to exist so it can prepend new release sections."
    )


def test_changelog_has_h1_and_release_marker(repo_root: Path) -> None:
    text = (repo_root / "CHANGELOG.md").read_text(encoding="utf-8")
    assert re.search(r"(?m)^# Changelog\b", text), (
        "CHANGELOG.md must start with a top-level '# Changelog' heading."
    )
    assert "<!-- RELEASES -->" in text, (
        "CHANGELOG.md must contain the '<!-- RELEASES -->' marker; the "
        "release workflow inserts new entries directly after this marker."
    )


def test_changelog_release_sections_are_semver(repo_root: Path) -> None:
    """Any '## [x.y.z]' headings (released entries) must be semver."""
    text = (repo_root / "CHANGELOG.md").read_text(encoding="utf-8")
    for match in re.finditer(r"(?m)^##\s+\[([^\]]+)\]", text):
        label = match.group(1)
        if label == "Unreleased":
            continue
        assert re.match(r"^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$", label), (
            f"CHANGELOG.md release heading '[{label}]' is not semver."
        )
