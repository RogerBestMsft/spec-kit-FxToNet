"""T018: dotnet-build.{sh,ps1} markers + exit-code propagation."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from ._helpers import require_bash, require_pwsh, run


def _ensure_dotnet_available() -> None:
    if not shutil.which("dotnet"):
        pytest.skip("dotnet SDK not available")


def test_dotnet_build_sh_markers(repo_root: Path, fixtures_dir: Path) -> None:
    _ensure_dotnet_available()
    bash = require_bash()
    script = repo_root / "fx-to-dotnet" / "scripts" / "bash" / "dotnet-build.sh"
    target = fixtures_dir / "HelloLib.csproj"
    result = run([bash, str(script), str(target)])
    # Assert returncode first so a build failure surfaces the actual dotnet
    # output rather than being masked by a missing-marker assertion.
    assert result.returncode == 0, f"build failed:\n{result.stdout}\n{result.stderr}"
    assert "::build-start::" in result.stdout
    assert "::build-end::" in result.stdout
    assert "exit-code:" in result.stdout


def test_dotnet_build_ps1_markers(repo_root: Path, fixtures_dir: Path) -> None:
    _ensure_dotnet_available()
    pwsh = require_pwsh()
    script = repo_root / "fx-to-dotnet" / "scripts" / "powershell" / "dotnet-build.ps1"
    target = fixtures_dir / "HelloLib.csproj"
    result = run([pwsh, "-NoProfile", "-File", str(script), str(target)])
    assert result.returncode == 0, f"build failed:\n{result.stdout}\n{result.stderr}"
    assert "::build-start::" in result.stdout
    assert "::build-end::" in result.stdout
    assert "exit-code:" in result.stdout


def test_dotnet_build_sh_propagates_failure(repo_root: Path, tmp_path: Path) -> None:
    _ensure_dotnet_available()
    bash = require_bash()
    script = repo_root / "fx-to-dotnet" / "scripts" / "bash" / "dotnet-build.sh"
    bogus = tmp_path / "DoesNotExist.csproj"
    bogus.write_text("<Project></Project>", encoding="utf-8")
    result = run([bash, str(script), str(bogus)])
    # Script disables -e around the dotnet invocation so structured markers
    # always emit, but the captured exit code MUST propagate non-zero.
    assert result.returncode != 0


def test_dotnet_build_ps1_propagates_failure(repo_root: Path, tmp_path: Path) -> None:
    _ensure_dotnet_available()
    pwsh = require_pwsh()
    script = repo_root / "fx-to-dotnet" / "scripts" / "powershell" / "dotnet-build.ps1"
    bogus = tmp_path / "DoesNotExist.csproj"
    bogus.write_text("<Project></Project>", encoding="utf-8")
    result = run([pwsh, "-NoProfile", "-File", str(script), str(bogus)])
    assert result.returncode != 0
