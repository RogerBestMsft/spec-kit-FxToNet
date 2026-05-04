"""Shared pytest fixtures for the fx-to-dotnet test suite."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest
import yaml


@pytest.fixture(scope="session")
def repo_root() -> Path:
    """Absolute path to the repository root."""
    return Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def extension_dir(repo_root: Path) -> Path:
    return repo_root / "fx-to-dotnet"


@pytest.fixture(scope="session")
def preset_dir(repo_root: Path) -> Path:
    return repo_root / "presets" / "fx-to-dotnet-sdd"


@pytest.fixture(scope="session")
def extension_yml(extension_dir: Path) -> dict:
    """Parsed `fx-to-dotnet/extension.yml`."""
    return yaml.safe_load((extension_dir / "extension.yml").read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def preset_yml(preset_dir: Path) -> dict:
    """Parsed `presets/fx-to-dotnet-sdd/preset.yml`."""
    return yaml.safe_load((preset_dir / "preset.yml").read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def workflow_ymls(extension_dir: Path) -> list[tuple[Path, dict]]:
    """All discovered workflow.yml files paired with their parsed contents."""
    out: list[tuple[Path, dict]] = []
    for path in sorted((extension_dir / "commands" / "workflows").glob("*/workflow.yml")):
        out.append((path, yaml.safe_load(path.read_text(encoding="utf-8"))))
    return out


@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    return Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def tmp_solution_fixture(tmp_path: Path, fixtures_dir: Path) -> Path:
    """Copy `tests/fixtures/fake-solution/` into a tmp dir; return its root."""
    src = fixtures_dir / "fake-solution"
    dst = tmp_path / "fake-solution"
    shutil.copytree(src, dst)
    return dst
