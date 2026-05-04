"""T022: parity diff across (*.ps1, *.sh|*.py) pairs in support_scripts/."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

from ._helpers import require_bash, require_pwsh, run


def _normalize(text: str) -> str:
    """Strip volatile output before diffing."""
    # Drop carriage returns; trim trailing whitespace per line; collapse blank runs.
    text = text.replace("\r", "")
    lines = [ln.rstrip() for ln in text.split("\n")]
    # Drop empty leading/trailing lines.
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def test_version_check_ps1_matches_py(repo_root: Path) -> None:
    pwsh = require_pwsh()
    py = run([sys.executable, str(repo_root / "support_scripts" / "version-check.py")], cwd=repo_root)
    ps = run(
        [pwsh, "-NoProfile", "-File", str(repo_root / "support_scripts" / "version-check.ps1")],
        cwd=repo_root,
    )
    assert py.returncode == ps.returncode == 0
    # Both must report the same final "OK: ... at version X" line.
    py_ver = re.search(r"at version (\S+)", py.stdout)
    ps_ver = re.search(r"at version (\S+)", ps.stdout)
    assert py_ver and ps_ver, f"missing version line:\npy:\n{py.stdout}\nps:\n{ps.stdout}"
    assert py_ver.group(1) == ps_ver.group(1)


def test_cross_reference_audit_ps1_matches_py(repo_root: Path) -> None:
    pwsh = require_pwsh()
    py = run(
        [sys.executable, str(repo_root / "support_scripts" / "cross-reference-audit.py")],
        cwd=repo_root,
    )
    ps = run(
        [pwsh, "-NoProfile", "-File", str(repo_root / "support_scripts" / "cross-reference-audit.ps1")],
        cwd=repo_root,
    )
    assert py.returncode == ps.returncode
    py_count = re.search(r"Found (\d+) declared commands", py.stdout)
    ps_count = re.search(r"Found (\d+) declared commands", ps.stdout)
    assert py_count and ps_count
    assert py_count.group(1) == ps_count.group(1)


def test_generate_catalog_ps1_matches_py(repo_root: Path) -> None:
    pwsh = require_pwsh()
    py = run(
        [sys.executable, str(repo_root / "support_scripts" / "generate-catalog.py")],
        cwd=repo_root,
    )
    ps = run(
        [pwsh, "-NoProfile", "-File", str(repo_root / "support_scripts" / "generate-catalog.ps1")],
        cwd=repo_root,
    )
    assert py.returncode == ps.returncode == 0
    py_data = json.loads(py.stdout)
    ps_data = json.loads(ps.stdout)
    # Compare core fields (id, version) — tolerate field-ordering differences.
    py_ids = sorted((e["id"], e["version"]) for e in py_data["extensions"] + py_data["presets"])
    ps_ids = sorted((e["id"], e["version"]) for e in ps_data["extensions"] + ps_data["presets"])
    assert py_ids == ps_ids


def test_bump_version_sh_matches_ps1_on_valid_input(repo_root: Path, tmp_path: Path) -> None:
    """Both bumpers should produce identical mutation given the same valid version."""
    import shutil as _sh
    bash = require_bash()
    pwsh = require_pwsh()

    def _clone(name: str) -> Path:
        d = tmp_path / name
        _sh.copytree(repo_root / "support_scripts", d / "support_scripts")
        (d / "fx-to-dotnet").mkdir()
        _sh.copy2(repo_root / "fx-to-dotnet" / "extension.yml", d / "fx-to-dotnet" / "extension.yml")
        return d

    sh_clone = _clone("sh")
    ps_clone = _clone("ps")

    r1 = run([bash, str(sh_clone / "support_scripts" / "bump-version.sh"), "1.2.3"], cwd=sh_clone)
    r2 = run(
        [pwsh, "-NoProfile", "-File",
         str(ps_clone / "support_scripts" / "bump-version.ps1"), "-Version", "1.2.3"],
        cwd=ps_clone,
    )
    assert r1.returncode == r2.returncode == 0
    sh_yaml = (sh_clone / "fx-to-dotnet" / "extension.yml").read_text(encoding="utf-8").replace("\r", "")
    ps_yaml = (ps_clone / "fx-to-dotnet" / "extension.yml").read_text(encoding="utf-8").replace("\r", "")
    assert sh_yaml == ps_yaml, "bump-version pair drift:\n--- sh ---\n" + sh_yaml + "\n--- ps ---\n" + ps_yaml
