"""T019: bump-version.{ps1,sh} mutates extension.yml; rejects bad input."""

from __future__ import annotations

import re
import shutil
from pathlib import Path

from ._helpers import require_bash, require_pwsh, run


def _make_repo_clone(src_root: Path, dst_root: Path) -> Path:
    """Copy support_scripts + fx-to-dotnet/extension.yml + presets into dst_root."""
    shutil.copytree(src_root / "support_scripts", dst_root / "support_scripts")
    (dst_root / "fx-to-dotnet").mkdir()
    shutil.copy2(
        src_root / "fx-to-dotnet" / "extension.yml",
        dst_root / "fx-to-dotnet" / "extension.yml",
    )
    return dst_root


def test_bump_version_sh_updates_yaml(repo_root: Path, tmp_path: Path) -> None:
    bash = require_bash()
    clone = _make_repo_clone(repo_root, tmp_path / "repo")
    result = run(
        [bash, str(clone / "support_scripts" / "bump-version.sh"), "9.9.9"],
        cwd=clone,
    )
    assert result.returncode == 0, result.stderr
    text = (clone / "fx-to-dotnet" / "extension.yml").read_text(encoding="utf-8")
    assert re.search(r'^\s+version:\s*"9\.9\.9"\s*$', text, re.MULTILINE)


def test_bump_version_sh_rejects_non_semver(repo_root: Path, tmp_path: Path) -> None:
    bash = require_bash()
    clone = _make_repo_clone(repo_root, tmp_path / "repo")
    result = run(
        [bash, str(clone / "support_scripts" / "bump-version.sh"), "abc"],
        cwd=clone,
    )
    assert result.returncode != 0


def test_bump_version_ps1_updates_yaml(repo_root: Path, tmp_path: Path) -> None:
    pwsh = require_pwsh()
    clone = _make_repo_clone(repo_root, tmp_path / "repo")
    result = run(
        [pwsh, "-NoProfile", "-File",
         str(clone / "support_scripts" / "bump-version.ps1"), "-Version", "9.9.9"],
        cwd=clone,
    )
    assert result.returncode == 0, result.stderr
    text = (clone / "fx-to-dotnet" / "extension.yml").read_text(encoding="utf-8")
    assert re.search(r'^\s+version:\s*"9\.9\.9"\s*$', text, re.MULTILINE)


def test_bump_version_ps1_rejects_non_semver(repo_root: Path, tmp_path: Path) -> None:
    pwsh = require_pwsh()
    clone = _make_repo_clone(repo_root, tmp_path / "repo")
    result = run(
        [pwsh, "-NoProfile", "-File",
         str(clone / "support_scripts" / "bump-version.ps1"), "-Version", "abc"],
        cwd=clone,
    )
    assert result.returncode != 0
