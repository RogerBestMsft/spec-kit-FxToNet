"""T025: thin command-driver helper.

Parses a command's markdown and exposes its declared MCP tool dependencies,
section structure, and frontmatter for runtime tests. This is intentionally
NOT a full LLM-driven executor — it surfaces the deterministic contract
between commands and MCP that CI can assert against.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml


FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
SECTION_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
MCP_CALL_RE = re.compile(r"`([A-Z][\w]+)\s*\(", re.MULTILINE)
SECTION_HEADER_RE = re.compile(r"^##\s+(\d+)\.\s+(.+?)\s*$", re.MULTILINE)


@dataclass
class CommandSpec:
    name: str
    path: Path
    frontmatter: dict
    body: str
    sections: list[tuple[int, str]] = field(default_factory=list)
    """Top-level numbered sections: list of (n, title) preserving file order."""

    @property
    def description(self) -> str:
        return self.frontmatter.get("description", "")

    @property
    def declared_commands(self) -> list[str]:
        return list(self.frontmatter.get("commands") or [])

    def has_section(self, title_substring: str) -> bool:
        return any(title_substring.lower() in t.lower() for _, t in self.sections)


def parse_command(path: Path) -> CommandSpec:
    text = path.read_text(encoding="utf-8")
    fm_match = FRONTMATTER_RE.match(text)
    fm: dict = {}
    body = text
    if fm_match:
        fm = yaml.safe_load(fm_match.group(1)) or {}
        body = text[fm_match.end():]
    sections = [(int(m.group(1)), m.group(2).strip())
                for m in SECTION_HEADER_RE.finditer(body)]
    return CommandSpec(
        name=path.stem,
        path=path,
        frontmatter=fm,
        body=body,
        sections=sections,
    )


def find_command(extension_dir: Path, command_name: str) -> Path:
    """Resolve a `speckit.fx-to-dotnet.<x>` command to its markdown file."""
    import yaml as _y
    manifest = _y.safe_load((extension_dir / "extension.yml").read_text(encoding="utf-8"))
    for cmd in manifest["provides"]["commands"]:
        if cmd["name"] == command_name:
            return extension_dir / cmd["file"]
    raise KeyError(f"Command not declared: {command_name}")


# --- Lightweight migration state writers (deterministic file-IO subset) ----

ANALYSIS_TEMPLATE = """\
# .NET Migration Analysis

## Solution
- path: {solution}

## Project Classifications
- Core/Core.csproj — library
- Data/Data.csproj — library
- Web/Web.csproj — web

## Dependencies
- Web -> Data -> Core

## Package Compatibility
{packages}

## Blockers
- (none)
"""

PACKAGE_UPDATES_TEMPLATE = """\
# Package Updates

## Recommended Upgrades
{packages}

## Execution State
- pending: yes
"""


def write_analysis(feature_dir: Path, solution: Path, packages: list[dict]) -> Path:
    pkg_lines = "\n".join(
        f"- {p['id']}: {p['current']} -> {p['recommended']}" for p in packages
    ) or "- (none)"
    out = feature_dir / "migration" / "analysis.md"
    out.write_text(
        ANALYSIS_TEMPLATE.format(solution=solution, packages=pkg_lines),
        encoding="utf-8",
    )
    return out


def write_package_updates(feature_dir: Path, packages: list[dict]) -> Path:
    pkg_lines = "\n".join(
        f"- {p['id']}: {p['current']} -> {p['recommended']}" for p in packages
    ) or "- (none)"
    out = feature_dir / "migration" / "package-updates.md"
    out.write_text(PACKAGE_UPDATES_TEMPLATE.format(packages=pkg_lines), encoding="utf-8")
    return out


ORCHESTRATION_TEMPLATE = """\
# Orchestration State

- solutionPath: {solution}
- targetFramework: {target}
- lastCompletedPhase: {phase}
- packageCompatStatus: {pkg_status}
- multitargetStatus: {mt_status}
- aspnetMigrationStatus: {aspnet_status}
"""


def write_orchestration(
    feature_dir: Path,
    solution: Path,
    target: str = "net10.0",
    last_completed_phase: str = "none",
    package_compat_status: str = "pending",
    multitarget_status: str = "pending",
    aspnet_migration_status: str = "pending",
) -> Path:
    out = feature_dir / "migration" / "orchestration.md"
    out.write_text(
        ORCHESTRATION_TEMPLATE.format(
            solution=solution,
            target=target,
            phase=last_completed_phase,
            pkg_status=package_compat_status,
            mt_status=multitarget_status,
            aspnet_status=aspnet_migration_status,
        ),
        encoding="utf-8",
    )
    return out


def read_orchestration(feature_dir: Path) -> dict[str, str]:
    text = (feature_dir / "migration" / "orchestration.md").read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for line in text.splitlines():
        m = re.match(r"^-\s*([\w]+):\s*(.+?)\s*$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out
