"""Structural tests for the per-phase validation commands."""

import pathlib
import re

import pytest
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXT_DIR = ROOT / "fx-to-dotnet"

VALIDATE_COMMANDS = [
    ("speckit.fx-to-dotnet.validate-sdk", "commands/validate-sdk/validate.md"),
    ("speckit.fx-to-dotnet.validate-packages", "commands/validate-packages/validate.md"),
    ("speckit.fx-to-dotnet.validate-multitarget", "commands/validate-multitarget/validate.md"),
    ("speckit.fx-to-dotnet.validate-web", "commands/validate-web/validate.md"),
]

_FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def _parse_frontmatter(text: str) -> dict:
    """Extract YAML frontmatter, handling --- inside YAML comments."""
    m = _FM_RE.match(text)
    assert m, "No frontmatter found"
    return yaml.safe_load(m.group(1)) or {}


@pytest.mark.parametrize("cmd_name,cmd_path", VALIDATE_COMMANDS)
def test_validate_command_file_exists(cmd_name, cmd_path):
    """Each validate command .md file must exist."""
    assert (EXT_DIR / cmd_path).is_file(), f"{cmd_path} not found"


@pytest.mark.parametrize("cmd_name,cmd_path", VALIDATE_COMMANDS)
def test_validate_command_has_valid_frontmatter(cmd_name, cmd_path):
    """Each validate command must have parseable YAML frontmatter with description and tools."""
    text = (EXT_DIR / cmd_path).read_text(encoding="utf-8")
    fm = _parse_frontmatter(text)
    assert "description" in fm, f"{cmd_path} frontmatter missing 'description'"
    assert "tools" in fm, f"{cmd_path} frontmatter missing 'tools'"


def test_validate_commands_registered_in_extension_yml():
    """All validate commands must be registered in extension.yml provides.commands."""
    ext_yml = (EXT_DIR / "extension.yml").read_text(encoding="utf-8")
    ext = yaml.safe_load(ext_yml)
    registered = {c["name"] for c in ext["provides"]["commands"]}
    for cmd_name, _ in VALIDATE_COMMANDS:
        assert cmd_name in registered, f"{cmd_name} not registered in extension.yml"


def test_validate_commands_in_orchestrator_commands_list():
    """All validate commands must be listed in orchestrate.md frontmatter commands."""
    orch_text = (EXT_DIR / "commands" / "orchestrate" / "orchestrate.md").read_text(
        encoding="utf-8"
    )
    fm = _parse_frontmatter(orch_text)
    orch_commands = fm.get("commands") or []
    for cmd_name, _ in VALIDATE_COMMANDS:
        assert cmd_name in orch_commands, (
            f"{cmd_name} not in orchestrate.md commands list"
        )
