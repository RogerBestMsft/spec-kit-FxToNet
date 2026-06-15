"""T016: extract JSON from mcp-setup/POLICY.md, validate, and run platform validators."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

from ._helpers import validate_with


JSON_BLOCK_RE = re.compile(r"```json\s*\n(.*?)\n```", re.DOTALL)


def _extract_json_blocks(text: str) -> list[str]:
    return JSON_BLOCK_RE.findall(text)


def test_mcp_setup_contains_valid_mcp_json(extension_dir: Path, repo_root: Path) -> None:
    md = (extension_dir / "policies" / "mcp-setup" / "POLICY.md").read_text(encoding="utf-8")
    blocks = _extract_json_blocks(md)
    assert blocks, "mcp-setup/POLICY.md has no ```json fenced blocks"

    found_mcp_servers = False
    found_servers = False
    required_server = "Microsoft.GitHubCopilot.Modernization.Mcp"

    for raw in blocks:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Invalid JSON block in mcp-setup/POLICY.md: {exc}\n{raw[:200]}")
        if not isinstance(data, dict):
            continue
        if "mcpServers" in data:
            # Schema validates the canonical mcpServers shape used by VS / Cursor / Windsurf / JetBrains / generic.
            validate_with(repo_root, "mcp-config.schema.json", data)
            assert required_server in data["mcpServers"], (
                f"mcpServers block missing required entry {required_server!r}"
            )
            found_mcp_servers = True
        elif "servers" in data:
            # VS Code variant: validate directly against VS Code schema.
            validate_with(repo_root, "mcp-config-vscode.schema.json", data)
            assert required_server in data["servers"], (
                f"servers block missing required entry {required_server!r}"
            )
            found_servers = True

    assert found_mcp_servers, (
        "No 'mcpServers' JSON block found in mcp-setup/POLICY.md "
        "(required for VS / Cursor / Windsurf / JetBrains / generic hosts)"
    )
    assert found_servers, (
        "No 'servers' JSON block found in mcp-setup/POLICY.md (required for VS Code host)"
    )


def test_mcp_config_validate_sh_succeeds(repo_root: Path) -> None:
    bash = shutil.which("bash")
    if not bash:
        pytest.skip("bash not available")
    # Detect Windows WSL stub (`bash.exe` shipped with Windows resolves to WSL,
    # which fails when no distro is installed).
    if os.name == "nt":
        probe = subprocess.run(
            [bash, "-c", "echo ok"],
            capture_output=True,
            text=True,
        )
        if probe.returncode != 0 or "ok" not in probe.stdout:
            pytest.skip(f"bash on Windows is non-functional (likely WSL stub): {probe.stdout!r}")
    script = repo_root / "support_scripts" / "mcp-config-validate.sh"
    result = subprocess.run(
        [bash, str(script)],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
    )
    assert result.returncode == 0, (
        f"mcp-config-validate.sh failed (exit {result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_mcp_config_validate_ps1_succeeds(repo_root: Path) -> None:
    pwsh = shutil.which("pwsh") or shutil.which("powershell")
    if not pwsh:
        pytest.skip("pwsh/powershell not available")
    script = repo_root / "support_scripts" / "mcp-config-validate.ps1"
    result = subprocess.run(
        [pwsh, "-NoProfile", "-File", str(script)],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
    )
    assert result.returncode == 0, (
        f"mcp-config-validate.ps1 failed (exit {result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_mcp_setup_host_detection_rules_complete(extension_dir: Path) -> None:
    """Verify POLICY.md documents all hosts, priority order, and multi-signal fallback."""
    md = (extension_dir / "policies" / "mcp-setup" / "POLICY.md").read_text(encoding="utf-8")

    # All 6 hosts must appear in the Host Matrix
    for host in ("Visual Studio", "VS Code", "Cursor", "Windsurf", "JetBrains", "Generic"):
        assert host in md, f"Host Matrix missing entry for {host!r}"

    # Priority order: VS before VS Code in detection rules
    vs_pos = md.index("1. **Visual Studio")
    vscode_pos = md.index("2. **VS Code")
    assert vs_pos < vscode_pos, "Visual Studio must be checked before VS Code"

    # Multi-signal fallback documented
    assert "ask-questions" in md, (
        "POLICY.md must document ask-questions fallback for multi-signal conflict"
    )

    # Prerequisites section exists
    assert "## Prerequisites" in md, "POLICY.md must have a ## Prerequisites section"
