"""T012: cross-reference audit (subprocess + re-implementation snapshot)."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


CROSS_REF_RE = re.compile(r"speckit\.fx-to-dotnet[\w-]*\.[\w-]+")
DISPATCH_TARGET_RE = re.compile(
    r"dispatch:\s*(speckit\.fx-to-dotnet\.[a-z0-9-]+)\(",
)


def test_cross_reference_audit_script_succeeds(repo_root: Path) -> None:
    script = repo_root / "support_scripts" / "cross-reference-audit.py"
    result = subprocess.run(
        [sys.executable, str(script)],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
    )
    assert result.returncode == 0, (
        f"cross-reference-audit.py failed (exit {result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_resolved_unresolved_snapshot(extension_dir: Path, extension_yml: dict) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    unresolved: list[str] = []
    for md in (extension_dir / "commands").glob("**/*.md"):
        for m in CROSS_REF_RE.finditer(md.read_text(encoding="utf-8")):
            ref = m.group(0)
            if ref not in declared:
                unresolved.append(f"{md.relative_to(extension_dir)}: {ref}")
    assert not unresolved, "Unresolved cross-references:\n  " + "\n  ".join(unresolved)


def test_tasks_hook_dispatch_targets_are_declared(
    extension_dir: Path, extension_yml: dict
) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    tasks_hook = extension_dir / "commands" / "hooks" / "tasks-hook.md"
    text = tasks_hook.read_text(encoding="utf-8")

    targets = {m.group(1) for m in DISPATCH_TARGET_RE.finditer(text)}
    assert targets, "No dispatch targets were found in tasks-hook.md"

    missing = sorted(t for t in targets if t not in declared)
    assert not missing, (
        "tasks-hook dispatch target(s) are not declared in extension.yml:\n  "
        + "\n  ".join(missing)
    )
