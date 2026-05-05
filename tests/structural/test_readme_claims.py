"""T014: README command tables match extension.yml provides."""

from __future__ import annotations

import re
from pathlib import Path


CMD_ROW_RE = re.compile(r"^\|\s*`(speckit\.fx-to-dotnet[\w.-]+)`\s*\|", re.MULTILINE)


def test_extension_readme_command_table_matches_manifest(
    extension_dir: Path, extension_yml: dict
) -> None:
    readme = (extension_dir / "README.md").read_text(encoding="utf-8")
    cited = set(CMD_ROW_RE.findall(readme))
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    not_declared = cited - declared
    assert not not_declared, (
        "README cites commands not declared in extension.yml:\n  "
        + "\n  ".join(sorted(not_declared))
    )


def test_extension_readme_cites_all_core_commands(
    extension_dir: Path, extension_yml: dict
) -> None:
    """All non-hook commands must appear in the README."""
    readme = (extension_dir / "README.md").read_text(encoding="utf-8")
    cited = set(CMD_ROW_RE.findall(readme))
    declared = [c["name"] for c in extension_yml["provides"]["commands"]]
    core = [n for n in declared if "-hook" not in n]
    missing = [n for n in core if n not in cited]
    assert not missing, "Core commands missing from README:\n  " + "\n  ".join(missing)


def test_root_readme_version_matches_manifest(repo_root: Path, extension_yml: dict) -> None:
    text = (repo_root / "README.md").read_text(encoding="utf-8")
    declared = extension_yml["extension"]["version"]
    # The root README has a line like: "Extension version: `0.7.0`"
    m = re.search(r"Extension version:\s*`([^`]+)`", text)
    if m:
        assert m.group(1) == declared, (
            f"Root README extension version `{m.group(1)}` != extension.yml `{declared}`"
        )


def test_root_readme_preset_version_matches_manifest(
    repo_root: Path, preset_yml: dict
) -> None:
    text = (repo_root / "README.md").read_text(encoding="utf-8")
    declared = preset_yml["preset"]["version"]
    m = re.search(r"Preset version:\s*`([^`]+)`", text)
    if m:
        assert m.group(1) == declared, (
            f"Root README preset version `{m.group(1)}` != preset.yml `{declared}`"
        )
