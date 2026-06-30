"""G7: policy `query=` ids in commands resolve to a `policies/<id>/` folder.

A command that calls `get_instructions(kind='policy', query='<id>')` must reference a
policy this extension actually ships, otherwise the load is a no-op at runtime and the
agent silently proceeds without the intended guidance.

`kind='scenario'` loads are intentionally NOT checked here (scenarios are provided by the
App Modernization MCP, not by this extension's `policies/` tree).
"""

from __future__ import annotations

import re
from pathlib import Path


POLICY_QUERY_RE = re.compile(
    r"get_instructions\(\s*kind=['\"]policy['\"]\s*,\s*query=['\"]([^'\"]+)['\"]"
)

# Policy ids that are intentionally provided outside this extension's policies/ tree.
# `scenario-initialization` is loaded during MCP scenario bootstrap and has no local
# policy folder; allowlisted pending confirmation it is core/MCP-provided (see TEST_PLAN).
EXTERNAL_POLICY_QUERIES = {"scenario-initialization"}


def _command_md_files(extension_dir: Path) -> list[Path]:
    return sorted(p for p in (extension_dir / "commands").glob("**/*.md") if p.is_file())


def _policy_ids(extension_dir: Path) -> set[str]:
    root = extension_dir / "policies"
    return {p.name for p in root.iterdir() if p.is_dir()}


def test_policy_queries_resolve_to_a_policy_folder(extension_dir: Path) -> None:
    available = _policy_ids(extension_dir) | EXTERNAL_POLICY_QUERIES
    errors: list[str] = []
    for md in _command_md_files(extension_dir):
        text = md.read_text(encoding="utf-8")
        rel = str(md.relative_to(extension_dir))
        for q in POLICY_QUERY_RE.findall(text):
            if q not in available:
                errors.append(f"{rel}: get_instructions(kind='policy', query='{q}') has no policies/{q}/")
    assert not errors, "Unresolved policy queries:\n  " + "\n  ".join(errors)


def test_every_shipped_policy_has_a_policy_md(extension_dir: Path) -> None:
    missing = sorted(
        pid for pid in _policy_ids(extension_dir)
        if not (extension_dir / "policies" / pid / "POLICY.md").is_file()
    )
    assert not missing, "Policy folders without POLICY.md:\n  " + "\n  ".join(missing)
