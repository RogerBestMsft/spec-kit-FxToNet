"""T015: wraps support_scripts/version-check.py."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def test_version_check_script_succeeds(repo_root: Path) -> None:
    script = repo_root / "support_scripts" / "version-check.py"
    result = subprocess.run(
        [sys.executable, str(script)],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
    )
    assert result.returncode == 0, (
        f"version-check.py failed (exit {result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
