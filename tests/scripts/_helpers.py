"""Helpers for script-tier tests."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest


def working_bash() -> str | None:
    """Return path to a usable bash, or None when only the WSL stub is present."""
    bash = shutil.which("bash")
    if not bash:
        return None
    if os.name == "nt":
        probe = subprocess.run(
            [bash, "-c", "echo ok"], capture_output=True, text=True
        )
        if probe.returncode != 0 or "ok" not in probe.stdout:
            return None
    return bash


def working_pwsh() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def require_bash() -> str:
    bash = working_bash()
    if not bash:
        pytest.skip("Functional bash not available")
    return bash


def require_pwsh() -> str:
    pwsh = working_pwsh()
    if not pwsh:
        pytest.skip("pwsh/powershell not available")
    return pwsh


def run(cmd: list[str], cwd: Path | None = None, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(cwd) if cwd else None,
        env=env,
    )
