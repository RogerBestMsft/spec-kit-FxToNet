"""G9: MCP tool references in command frontmatter are declared in requires.tools.

Command `tools` lists mix host tools (`read`, `search`, `vscode/...`, `execute/...`)
with MCP server tools written as `<server-id>/<tool>` where `<server-id>` is a
reverse-DNS id (e.g. `microsoft.githubcopilot.modernization.mcp/*`). Every MCP server a
command references must be declared under `requires.tools` in `extension.yml`, otherwise
the dependency is invisible to hosts and the tool will not be available at runtime.

Host tool namespaces (`vscode`, `execute`, `read`, ...) contain no dot and are ignored.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml


FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)


def _frontmatter(text: str) -> dict:
    m = FRONTMATTER_RE.match(text)
    return (yaml.safe_load(m.group(1)) or {}) if m else {}


def _command_md_files(extension_dir: Path) -> list[Path]:
    return sorted(p for p in (extension_dir / "commands").glob("**/*.md") if p.is_file())


def _required_servers(extension_yml: dict) -> set[str]:
    return {t.lower() for t in (extension_yml.get("requires", {}).get("tools") or [])}


def test_mcp_tool_refs_are_declared_in_requires(
    extension_dir: Path, extension_yml: dict
) -> None:
    required = _required_servers(extension_yml)
    errors: list[str] = []
    for md in _command_md_files(extension_dir):
        fm = _frontmatter(md.read_text(encoding="utf-8"))
        rel = str(md.relative_to(extension_dir))
        for tool in fm.get("tools") or []:
            if not isinstance(tool, str) or "/" not in tool:
                continue
            server = tool.split("/", 1)[0]
            if "." not in server:
                continue  # host-tool namespace (vscode/execute/read/...), not an MCP server
            if server.lower() not in required:
                errors.append(f"{rel}: MCP tool '{tool}' -> server '{server}' not in requires.tools")
    assert not errors, (
        "MCP tool references not backed by requires.tools in extension.yml:\n  "
        + "\n  ".join(errors)
    )
