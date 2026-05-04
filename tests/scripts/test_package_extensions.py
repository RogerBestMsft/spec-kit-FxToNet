"""T020: package-extensions.{ps1,sh} produces a bundle matching CI smoke pack."""

from __future__ import annotations

import os
import shutil
import zipfile
from pathlib import Path

import pytest

from ._helpers import require_bash, require_pwsh, run


def _names(zip_path: Path) -> list[str]:
    with zipfile.ZipFile(zip_path) as z:
        return z.namelist()


def _bundle_contents_ok(zip_path: Path) -> tuple[bool, list[str]]:
    names = _names(zip_path)
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


def _single_subdir_ok(zip_path: Path, subdir: str, manifest: str) -> tuple[bool, list[str]]:
    names = _names(zip_path)
    issues: list[str] = []
    if not any(n.endswith(f"{subdir}/{manifest}") for n in names):
        issues.append(f"missing {subdir}/{manifest}")
    # Top-level entries (paths without a leading directory other than `subdir`)
    top_dirs = {n.split("/", 1)[0] for n in names if "/" in n}
    extra = top_dirs - {subdir}
    if extra:
        issues.append(f"unexpected top-level entries: {sorted(extra)}")
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

    all_zips = sorted(releases.glob("*.zip"))
    assert len(all_zips) == 3, f"expected 3 zips, got {len(all_zips)}: {all_zips}"

    bundle_zips = [z for z in all_zips if z.name.startswith("fx-to-dotnet-") and "extension" not in z.name and "sdd" not in z.name]
    ext_zips    = list(releases.glob("fx-to-dotnet-extension-*.zip"))
    preset_zips = list(releases.glob("fx-to-dotnet-sdd-*.zip"))
    assert len(bundle_zips) == 1, f"expected 1 bundle zip, got {bundle_zips}"
    assert len(ext_zips) == 1,    f"expected 1 extension zip, got {ext_zips}"
    assert len(preset_zips) == 1, f"expected 1 preset zip, got {preset_zips}"

    ok, issues = _bundle_contents_ok(bundle_zips[0])
    assert ok, "bundle layout issues:\n  " + "\n  ".join(issues)

    ok, issues = _single_subdir_ok(ext_zips[0], "fx-to-dotnet", "extension.yml")
    assert ok, "extension zip layout issues:\n  " + "\n  ".join(issues)

    ok, issues = _single_subdir_ok(preset_zips[0], "fx-to-dotnet-sdd", "preset.yml")
    assert ok, "preset zip layout issues:\n  " + "\n  ".join(issues)
