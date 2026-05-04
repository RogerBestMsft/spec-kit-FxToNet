"""T013: every policy/POLICY.md referenced from a command body exists."""

from __future__ import annotations

import re
from pathlib import Path


POLICY_REF_RE = re.compile(r"policies/[\w./-]+?\.md")


def test_every_referenced_policy_target_exists(extension_dir: Path) -> None:
    missing: list[str] = []
    for md in (extension_dir / "commands").glob("**/*.md"):
        text = md.read_text(encoding="utf-8")
        for m in POLICY_REF_RE.finditer(text):
            ref = m.group(0)
            target = extension_dir / ref
            if not target.is_file():
                missing.append(f"{md.relative_to(extension_dir)}: {ref}")
    assert not missing, "Unresolved policy references:\n  " + "\n  ".join(sorted(set(missing)))
