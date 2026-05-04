"""T020: package-extensions.{ps1,sh} produces a bundle matching CI smoke pack."""

from __future__ import annotations

import os
import shutil
import zipfile
from pathlib import Path

import pytest

from ._helpers import require_bash, require_pwsh, run


def _bundle_contents_ok(zip_path: Path) -> tuple[bool, list[str]]:
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
    has_ext_yml = any(n.endswith("fx-to-dotnet/extension.yml") for n in names)
    has_preset_yml = any(n.endswith("fx-to-dotnet-sdd/preset.yml") for n in names)
    has_command = any(
        n.startswith("fx-to-dotnet/commands/") and n.endswith(".md") for n in names
    )
    issues: list[str] = []
    if not has_ext_yml:
        issues.append("missing fx-to-dotnet/extension.yml")
    if not has_preset_yml:
        issues.append("missing fx-to-dotnet-sdd/preset.yml")
    if not has_command:
        issues.append("missing any fx-to-dotnet/commands/**/*.md")
    return not issues, issues


@pytest.mark.parametrize(
    "shell",
    [
        pytest.param("sh", id="bash"),
        pytest.param("ps1", id="pwsh"),
    ],
)
def test_package_extensions_produces_bundle(repo_root: Path, tmp_path: Path, shell: str) -> None:
    if shell == "sh":
        runner = require_bash()
        script = repo_root / "support_scripts" / "package-extensions.sh"
        if not shutil.which("zip"):
            pytest.skip("`zip` CLI not available")
        cmd = [runner, str(script)]
    else:
        runner = require_pwsh()
        script = repo_root / "support_scripts" / "package-extensions.ps1"
        cmd = [runner, "-NoProfile", "-File", str(script)]

    releases = tmp_path / "releases"
    releases.mkdir()
    env = os.environ.copy()
    env["RELEASES_DIR"] = str(releases)

    result = run(cmd, cwd=repo_root, env=env)
    assert result.returncode == 0, (
        f"packager failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    zips = list(releases.glob("fx-to-dotnet-*.zip"))
    assert len(zips) == 1, f"expected 1 bundle zip, got {len(zips)}: {zips}"

    ok, issues = _bundle_contents_ok(zips[0])
    assert ok, "bundle layout issues:\n  " + "\n  ".join(issues)
