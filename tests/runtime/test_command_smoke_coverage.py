"""G6: deterministic runtime smoke coverage for commands lacking a dedicated smoke.

The runtime tier already covers `assess`, the hooks, and the orchestrator. This file
closes the gap for the remaining agent-facing commands. It is intentionally NOT an LLM
executor — it parses each command via the driver, asserts its declared contract
(description, tools, resolvable refs, on-disk scripts), and exercises the deterministic
command<->MCP edges that have a mock handler.
"""

from __future__ import annotations

import pytest

from ._driver import find_command, parse_command


# Commands that previously had no runtime smoke.
SMOKE_COMMANDS = [
    "speckit.fx-to-dotnet.convert",
    "speckit.fx-to-dotnet.fix",
    "speckit.fx-to-dotnet.update-packages",
    "speckit.fx-to-dotnet.web-migrate",
    "speckit.fx-to-dotnet.multitarget-migrate",
    "speckit.fx-to-dotnet.detect",
    "speckit.fx-to-dotnet.inventory",
    "speckit.fx-to-dotnet.mcp-preflight",
]


@pytest.fixture
def declared_names(extension_yml: dict) -> set[str]:
    return {c["name"] for c in extension_yml["provides"]["commands"]}


@pytest.mark.parametrize("command_name", SMOKE_COMMANDS)
def test_command_contract_smoke(
    command_name: str, extension_dir, extension_yml: dict, declared_names: set[str]
) -> None:
    path = find_command(extension_dir, command_name)
    assert path.is_file(), f"{command_name} -> {path} missing"

    spec = parse_command(path)

    # Frontmatter contract.
    assert spec.description.strip(), f"{command_name}: empty description"
    tools = spec.frontmatter.get("tools")
    assert isinstance(tools, list) and tools, f"{command_name}: tools must be a non-empty list"

    # Body is substantive (real agent instructions, not a stub).
    assert len(spec.body.strip()) > 200, f"{command_name}: body too small"

    # Every referenced command / handoff agent resolves.
    for ref in spec.declared_commands:
        assert ref in declared_names, f"{command_name}: unresolved command ref {ref}"
    for handoff in spec.frontmatter.get("handoffs") or []:
        agent = handoff.get("agent") if isinstance(handoff, dict) else None
        if isinstance(agent, str) and agent.startswith("speckit.fx-to-dotnet"):
            assert agent in declared_names, f"{command_name}: unresolved handoff {agent}"

    # Declared scripts (if any) exist on disk.
    manifest = {c["name"]: c for c in extension_yml["provides"]["commands"]}
    for s in manifest[command_name].get("scripts") or []:
        assert (extension_dir / s).is_file(), f"{command_name}: missing script {s}"


def test_convert_declares_sdk_tool_and_mock_responds(extension_dir, mock_mcp) -> None:
    """convert wires the SDK-style conversion MCP tool; the mock honors the contract."""
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.convert"))
    tools_blob = " ".join(spec.frontmatter.get("tools") or [])
    assert "convert_project_to_sdk_style" in tools_blob

    result = mock_mcp.call("convert_project_to_sdk_style", {"project": "Core/Core.csproj"})
    assert result["converted"] is True
    assert mock_mcp.calls_to("convert_project_to_sdk_style")


def test_fix_wires_build_script_and_documents_marker(extension_dir, extension_yml: dict) -> None:
    """fix owns the dotnet-build helper and instructs running builds through it."""
    manifest = {c["name"]: c for c in extension_yml["provides"]["commands"]}
    scripts = manifest["speckit.fx-to-dotnet.fix"].get("scripts") or []
    assert any(s.endswith("dotnet-build.sh") for s in scripts)
    assert any(s.endswith("dotnet-build.ps1") for s in scripts)

    body = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.fix")).body
    assert "dotnet-build" in body, "fix must instruct running builds via the build script"
