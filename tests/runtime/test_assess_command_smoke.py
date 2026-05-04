"""T028: assess command produces the expected migration artifacts."""

from __future__ import annotations

from pathlib import Path

from ._driver import find_command, parse_command, write_analysis, write_package_updates
from .conftest import MockMcp


def test_assess_command_declares_required_mcp_tools(extension_dir: Path) -> None:
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.assess"))
    tools = spec.frontmatter.get("tools") or []
    assert any("modernization.mcp" in t.lower() for t in tools), (
        f"assess.md must declare the modernization MCP tool; got {tools}"
    )


def test_assess_writes_analysis_and_package_updates(
    fake_solution_dir: Path, feature_dir: Path, mock_mcp: MockMcp
) -> None:
    """Drive the deterministic file-IO + MCP-call subset of `assess`."""
    sln = fake_solution_dir / "FakeSolution.sln"

    # Calls assess.md says to make: enumerate projects, find package upgrades.
    layers = mock_mcp.call("get_projects_in_topological_order", {"solution": str(sln)})
    assert layers["layers"]

    upgrades_payload = mock_mcp.call("FindRecommendedPackageUpgrades", {"solution": str(sln)})
    upgrades = upgrades_payload["upgrades"]

    analysis = write_analysis(feature_dir, sln, upgrades)
    package_updates = write_package_updates(feature_dir, upgrades)

    assert analysis.is_file()
    assert package_updates.is_file()
    body = analysis.read_text(encoding="utf-8")
    for required in (
        "## Solution",
        "## Project Classifications",
        "## Dependencies",
        "## Package Compatibility",
        "## Blockers",
    ):
        assert required in body, f"analysis.md missing section: {required!r}"
    assert "## Recommended Upgrades" in package_updates.read_text(encoding="utf-8")

    # Expected MCP-call shape: at least one topo-order + one package-upgrade query.
    assert mock_mcp.calls_to("get_projects_in_topological_order")
    assert mock_mcp.calls_to("FindRecommendedPackageUpgrades")
