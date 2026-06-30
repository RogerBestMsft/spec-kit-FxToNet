"""G3: policy-proof contract (markers-only).

Golden rule #6: a command that loads a domain policy via
`get_instructions(kind='policy', query='<id>')` must also emit a `## Policies Applied`
table so the citation is provable. This test enforces the two literal markers; it does
not validate the table's rows (kept deliberately loose to avoid brittleness).
"""

from __future__ import annotations

import re
from pathlib import Path


POLICY_LOAD_RE = re.compile(r"get_instructions\(\s*kind=['\"]policy['\"]", re.IGNORECASE)
POLICIES_APPLIED_RE = re.compile(r"^##\s+Policies Applied\s*$", re.MULTILINE)


def _command_md_files(extension_dir: Path) -> list[Path]:
    return sorted(p for p in (extension_dir / "commands").glob("**/*.md") if p.is_file())


def test_policy_loading_commands_emit_policies_applied(extension_dir: Path) -> None:
    """Any command that loads a policy must contain a `## Policies Applied` heading."""
    offenders: list[str] = []
    for md in _command_md_files(extension_dir):
        text = md.read_text(encoding="utf-8")
        if POLICY_LOAD_RE.search(text) and not POLICIES_APPLIED_RE.search(text):
            offenders.append(str(md.relative_to(extension_dir)))
    assert not offenders, (
        "Commands load a policy via get_instructions but never emit a "
        "`## Policies Applied` table (policy-proof contract):\n  " + "\n  ".join(offenders)
    )


def test_policies_applied_only_when_policies_loaded(extension_dir: Path) -> None:
    """A `## Policies Applied` table must be backed by at least one policy load."""
    offenders: list[str] = []
    for md in _command_md_files(extension_dir):
        text = md.read_text(encoding="utf-8")
        if POLICIES_APPLIED_RE.search(text) and not POLICY_LOAD_RE.search(text):
            offenders.append(str(md.relative_to(extension_dir)))
    assert not offenders, (
        "Commands emit a `## Policies Applied` table without any "
        "get_instructions(kind='policy', ...) load:\n  " + "\n  ".join(offenders)
    )


def test_at_least_one_command_proves_policies(extension_dir: Path) -> None:
    """Guard against the contract silently matching nothing (e.g. a regex regression)."""
    proven = [
        md.name
        for md in _command_md_files(extension_dir)
        if POLICY_LOAD_RE.search(md.read_text(encoding="utf-8"))
        and POLICIES_APPLIED_RE.search(md.read_text(encoding="utf-8"))
    ]
    assert proven, "Expected at least one command to load and prove policies"
