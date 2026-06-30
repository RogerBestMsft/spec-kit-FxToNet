"""G1: every extension script is declared, and every referenced extension-script
path in command/policy markdown resolves to a declared, on-disk script.

Closes the gap where a `scripts/{bash,powershell}/*` helper can be referenced from a
command body or policy (or shipped on disk) without being wired into any command's
`scripts:` array in `extension.yml`.
"""

from __future__ import annotations

import re
from pathlib import Path


# Matches `scripts/bash/foo.sh` or `fx-to-dotnet/scripts/powershell/Foo.ps1` anywhere.
SCRIPT_PATH_RE = re.compile(r"(?:fx-to-dotnet/)?(scripts/(?:bash|powershell)/[\w.-]+\.(?:sh|ps1))")


def _declared_scripts(extension_yml: dict) -> set[str]:
    declared: set[str] = set()
    for cmd in extension_yml["provides"]["commands"]:
        for s in cmd.get("scripts") or []:
            declared.add(s.replace("\\", "/"))
    return declared


def _on_disk_scripts(extension_dir: Path) -> set[str]:
    scripts_root = extension_dir / "scripts"
    found: set[str] = set()
    for sub in ("bash", "powershell"):
        d = scripts_root / sub
        if not d.is_dir():
            continue
        for p in d.iterdir():
            if p.is_file() and p.suffix in (".sh", ".ps1"):
                found.add(f"scripts/{sub}/{p.name}")
    return found


def _markdown_files(extension_dir: Path) -> list[Path]:
    roots = [extension_dir / "commands", extension_dir / "policies"]
    files: list[Path] = []
    for root in roots:
        if root.is_dir():
            files.extend(p for p in root.glob("**/*.md") if p.is_file())
    return sorted(files)


def test_every_on_disk_script_is_declared(extension_dir: Path, extension_yml: dict) -> None:
    """No orphan scripts: each file under scripts/{bash,powershell} is declared."""
    declared = _declared_scripts(extension_yml)
    on_disk = _on_disk_scripts(extension_dir)
    orphans = sorted(on_disk - declared)
    assert not orphans, (
        "Script files present on disk but not declared in any command's `scripts:` "
        "array in extension.yml:\n  " + "\n  ".join(orphans)
    )


def test_every_declared_script_exists(extension_dir: Path, extension_yml: dict) -> None:
    declared = _declared_scripts(extension_yml)
    missing = sorted(s for s in declared if not (extension_dir / s).is_file())
    assert not missing, "Declared scripts missing on disk:\n  " + "\n  ".join(missing)


def test_referenced_script_paths_are_declared(
    extension_dir: Path, extension_yml: dict
) -> None:
    """Every `scripts/{bash,powershell}/*` path mentioned in command or policy
    markdown must be a declared, on-disk script."""
    declared = _declared_scripts(extension_yml)
    on_disk = _on_disk_scripts(extension_dir)
    errors: list[str] = []
    for md in _markdown_files(extension_dir):
        text = md.read_text(encoding="utf-8")
        rel = str(md.relative_to(extension_dir))
        for m in SCRIPT_PATH_RE.finditer(text):
            ref = m.group(1)
            if ref not in on_disk:
                errors.append(f"{rel}: references missing script {ref}")
            elif ref not in declared:
                errors.append(f"{rel}: references undeclared script {ref}")
    assert not errors, (
        "Extension-script references not declared/on-disk:\n  " + "\n  ".join(sorted(set(errors)))
    )
