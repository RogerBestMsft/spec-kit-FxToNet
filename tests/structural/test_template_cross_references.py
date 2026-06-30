"""G8: cross-references inside preset templates resolve to declared commands.

`test_cross_references.py` and the cross-reference audit only scan `commands/**`. The
preset's `templates/**` (overrides of `specify/plan/tasks/implement` plus
`plan-template.md`) also mention `speckit.fx-to-dotnet.*` commands; a renamed or removed
command would leave a dangling reference there that nothing else catches.
"""

from __future__ import annotations

import re
from pathlib import Path


CROSS_REF_RE = re.compile(r"speckit\.fx-to-dotnet\.[a-z0-9-]+")


def _template_files(extension_dir: Path) -> list[Path]:
    root = extension_dir / "templates"
    return sorted(p for p in root.glob("**/*.md") if p.is_file())


def test_template_references_resolve(extension_dir: Path, extension_yml: dict) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    errors: list[str] = []
    for md in _template_files(extension_dir):
        text = md.read_text(encoding="utf-8")
        rel = str(md.relative_to(extension_dir))
        for ref in sorted(set(CROSS_REF_RE.findall(text))):
            if ref not in declared:
                errors.append(f"{rel}: unresolved reference {ref}")
    assert not errors, "Dangling command references in preset templates:\n  " + "\n  ".join(errors)


def test_templates_are_scanned(extension_dir: Path) -> None:
    """Guard against the glob silently matching nothing (e.g. a moved templates dir)."""
    assert _template_files(extension_dir), "Expected preset template markdown under templates/"
