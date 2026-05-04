"""T011: command markdown frontmatter parses and references resolve."""

from __future__ import annotations

import re
from pathlib import Path

import yaml


FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)


def _frontmatter(text: str) -> dict | None:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None
    return yaml.safe_load(m.group(1)) or {}


def _command_md_files(extension_dir: Path) -> list[Path]:
    cmds = extension_dir / "commands"
    return sorted(p for p in cmds.glob("**/*.md") if p.is_file())


def test_every_command_md_has_frontmatter(extension_dir: Path) -> None:
    missing: list[str] = []
    for md in _command_md_files(extension_dir):
        text = md.read_text(encoding="utf-8")
        if _frontmatter(text) is None:
            missing.append(str(md.relative_to(extension_dir)))
    assert not missing, "Missing/invalid frontmatter:\n  " + "\n  ".join(missing)


def test_every_frontmatter_has_description(extension_dir: Path) -> None:
    bad: list[str] = []
    for md in _command_md_files(extension_dir):
        fm = _frontmatter(md.read_text(encoding="utf-8")) or {}
        desc = fm.get("description")
        if not isinstance(desc, str) or not desc.strip():
            bad.append(str(md.relative_to(extension_dir)))
    assert not bad, "Missing/empty description:\n  " + "\n  ".join(bad)


def test_tools_field_is_list_when_present(extension_dir: Path) -> None:
    bad: list[str] = []
    for md in _command_md_files(extension_dir):
        fm = _frontmatter(md.read_text(encoding="utf-8")) or {}
        if "tools" in fm and not isinstance(fm["tools"], list):
            bad.append(str(md.relative_to(extension_dir)))
    assert not bad, "tools must be a list:\n  " + "\n  ".join(bad)


def test_referenced_commands_in_frontmatter_resolve(
    extension_dir: Path, extension_yml: dict
) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    errors: list[str] = []
    for md in _command_md_files(extension_dir):
        fm = _frontmatter(md.read_text(encoding="utf-8")) or {}
        rel = str(md.relative_to(extension_dir))

        for ref in fm.get("commands") or []:
            if isinstance(ref, str) and ref not in declared:
                errors.append(f"{rel}: commands -> {ref}")

        for handoff in fm.get("handoffs") or []:
            if isinstance(handoff, dict):
                agent = handoff.get("agent")
                if isinstance(agent, str) and agent.startswith("speckit.fx-to-dotnet") and agent not in declared:
                    errors.append(f"{rel}: handoff agent -> {agent}")

    assert not errors, "Undeclared command refs in frontmatter:\n  " + "\n  ".join(errors)
