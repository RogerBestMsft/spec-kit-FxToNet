"""T021: generate-catalog.{py,ps1} emits valid JSON with required keys."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from ._helpers import require_pwsh, run


REQUIRED_TOP = {"extensions", "presets"}
REQUIRED_ENTRY = {"id", "name", "version", "description", "url", "tags", "family"}


def _assert_valid(payload: str) -> None:
    data = json.loads(payload)
    assert REQUIRED_TOP.issubset(data.keys()), f"missing top keys: {data.keys()}"
    for ent in data["extensions"] + data["presets"]:
        missing = REQUIRED_ENTRY - ent.keys()
        assert not missing, f"entry {ent.get('id')} missing keys: {missing}"


def test_generate_catalog_py(repo_root: Path) -> None:
    script = repo_root / "support_scripts" / "generate-catalog.py"
    result = run([sys.executable, str(script)], cwd=repo_root)
    assert result.returncode == 0, result.stderr
    _assert_valid(result.stdout)


def test_generate_catalog_ps1(repo_root: Path) -> None:
    pwsh = require_pwsh()
    script = repo_root / "support_scripts" / "generate-catalog.ps1"
    result = run([pwsh, "-NoProfile", "-File", str(script)], cwd=repo_root)
    assert result.returncode == 0, result.stderr
    _assert_valid(result.stdout)
