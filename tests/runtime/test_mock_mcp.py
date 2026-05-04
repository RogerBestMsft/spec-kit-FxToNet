"""T024 sanity: mock MCP responds to canned tool calls."""

from __future__ import annotations

from .conftest import MockMcp


def test_mock_mcp_default_handlers_respond(mock_mcp: MockMcp) -> None:
    state = mock_mcp.call("get_state", {})
    assert state["lastCompletedPhase"] == "none"

    layers = mock_mcp.call("get_projects_in_topological_order", {"solution": "x.sln"})
    assert layers["layers"] and len(layers["layers"]) == 3

    upgrades = mock_mcp.call("FindRecommendedPackageUpgrades", {"project": "Web/Web.csproj"})
    assert upgrades["upgrades"][0]["id"] == "Newtonsoft.Json"


def test_mock_mcp_records_calls(mock_mcp: MockMcp) -> None:
    mock_mcp.call("get_state", {"k": 1})
    mock_mcp.call("get_state", {"k": 2})
    mock_mcp.call("ComputeDependencyLayers", {})
    assert len(mock_mcp.calls) == 3
    assert len(mock_mcp.calls_to("get_state")) == 2


def test_mock_mcp_custom_handler_overrides_default(mock_mcp: MockMcp) -> None:
    mock_mcp.register("get_state", lambda p: {"phase": "X", "lastCompletedPhase": "assessment"})
    assert mock_mcp.call("get_state", {})["lastCompletedPhase"] == "assessment"


def test_mock_mcp_unknown_tool_raises(mock_mcp: MockMcp) -> None:
    import pytest
    with pytest.raises(KeyError):
        mock_mcp.call("DoesNotExist", {})
