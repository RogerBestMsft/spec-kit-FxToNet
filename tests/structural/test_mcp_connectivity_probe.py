"""T030: MCP connectivity probe script validation."""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture
def probe_ps1(repo_root: Path) -> Path:
    return repo_root / "fx-to-dotnet" / "scripts" / "powershell" / "Mcp-ConnectivityCheck.ps1"


@pytest.fixture
def probe_sh(repo_root: Path) -> Path:
    return repo_root / "fx-to-dotnet" / "scripts" / "bash" / "mcp-connectivity-check.sh"


def test_probe_scripts_exist(probe_ps1: Path, probe_sh: Path) -> None:
    """Connectivity probe scripts must exist in the deployed scripts directory."""
    assert probe_ps1.is_file(), "Mcp-ConnectivityCheck.ps1 must exist under fx-to-dotnet/scripts/powershell/"
    assert probe_sh.is_file(), "mcp-connectivity-check.sh must exist under fx-to-dotnet/scripts/bash/"


def test_probe_output_schema(probe_ps1: Path, probe_sh: Path) -> None:
    """Both scripts must reference the three required JSON output fields."""
    for script in (probe_ps1, probe_sh):
        text = script.read_text(encoding="utf-8")
        for field in ("dnxFound", "packageResolvable", "error"):
            assert field in text, f"{script.name} missing JSON field {field!r}"


def test_probe_checks_dnx_on_path(probe_ps1: Path, probe_sh: Path) -> None:
    """Both scripts must check for dnx availability."""
    ps1_text = probe_ps1.read_text(encoding="utf-8")
    sh_text = probe_sh.read_text(encoding="utf-8")
    assert "dnx" in ps1_text
    assert "command -v dnx" in sh_text


def test_probe_references_nuget_feed(probe_ps1: Path, probe_sh: Path) -> None:
    """Both scripts must reference the NuGet feed URL."""
    for script in (probe_ps1, probe_sh):
        text = script.read_text(encoding="utf-8")
        assert "https://api.nuget.org/v3/index.json" in text, (
            f"{script.name} must reference the NuGet feed URL"
        )


def test_probe_registered_in_extension_yml(repo_root: Path) -> None:
    """The connectivity probe scripts must be registered in extension.yml under mcp-preflight."""
    ext_yml = (repo_root / "fx-to-dotnet" / "extension.yml").read_text(encoding="utf-8")
    assert "mcp-connectivity-check.sh" in ext_yml, (
        "mcp-connectivity-check.sh must be registered in extension.yml"
    )
    assert "Mcp-ConnectivityCheck.ps1" in ext_yml, (
        "Mcp-ConnectivityCheck.ps1 must be registered in extension.yml"
    )
