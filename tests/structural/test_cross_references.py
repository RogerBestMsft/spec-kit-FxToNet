"""T012: cross-reference audit (subprocess + re-implementation snapshot)."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


CROSS_REF_RE = re.compile(r"speckit\.fx-to-dotnet[\w-]*\.[\w-]+")


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
