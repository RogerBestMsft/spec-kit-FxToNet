"""T018: dotnet-build.{sh,ps1} markers + exit-code propagation."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from ._helpers import require_bash, require_pwsh, run


def _ensure_dotnet_available() -> None:
    if not shutil.which("dotnet"):
        pytest.skip("dotnet SDK not available")


def _isolated_project(fixtures_dir: Path, tmp_path: Path) -> Path:
    """Copy the HelloLib fixture into an isolated tmp dir.

    pytest-xdist runs tests in parallel; sharing the fixture's obj/ directory
    between the sh and ps1 build tests causes NuGet restore races
    ("Cannot create a file when that file already exists"). Each test gets
    its own copy so restore/build outputs do not collide.
    """
    dest = tmp_path / "HelloLib"
    dest.mkdir()
    for name in ("HelloLib.csproj", "Class1.cs"):
        shutil.copy2(fixtures_dir / name, dest / name)
    return dest / "HelloLib.csproj"


def test_dotnet_build_sh_markers(repo_root: Path, fixtures_dir: Path, tmp_path: Path) -> None:
    _ensure_dotnet_available()
    bash = require_bash()
    script = repo_root / "fx-to-dotnet" / "scripts" / "bash" / "dotnet-build.sh"
    target = _isolated_project(fixtures_dir, tmp_path)
    result = run([bash, str(script), str(target)])
    # Assert returncode first so a build failure surfaces the actual dotnet
    # output rather than being masked by a missing-marker assertion.
    assert result.returncode == 0, f"build failed:\n{result.stdout}\n{result.stderr}"
    assert "::build-start::" in result.stdout
    assert "::build-end::" in result.stdout
    assert "exit-code:" in result.stdout


def test_dotnet_build_ps1_markers(repo_root: Path, fixtures_dir: Path, tmp_path: Path) -> None:
    _ensure_dotnet_available()
    pwsh = require_pwsh()
    script = repo_root / "fx-to-dotnet" / "scripts" / "powershell" / "dotnet-build.ps1"
    target = _isolated_project(fixtures_dir, tmp_path)
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
