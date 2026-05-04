"""Runtime/L3 fixtures: in-process mock MCP responder + fake_solution_dir.

The mock MCP is an in-process responder (not stdio) that exposes the canned
tool calls a command would make through `invoke-tool`. Tests inject this mock
in lieu of the real MCP server. A separate stdio adapter is provided for
integration tests that genuinely need a subprocess channel.
"""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any, Callable

import pytest


# ---- Mock MCP responder (in-process) ---------------------------------------

class MockMcp:
    """Hand-rolled stub for the MCP servers used by fx-to-dotnet commands.

    Impersonates `Microsoft.GitHubCopilot.Modernization.Mcp` and
    `Swick.Mcp.Fx2dotnet`. Records every call for later assertion.
    """

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self._handlers: dict[str, Callable[[dict[str, Any]], Any]] = {}
        self._register_default_handlers()

    # ---- registration ----------------------------------------------------
    def register(self, tool: str, handler: Callable[[dict[str, Any]], Any]) -> None:
        self._handlers[tool] = handler

    def call(self, tool: str, params: dict[str, Any] | None = None) -> Any:
        params = params or {}
        self.calls.append((tool, params))
        if tool not in self._handlers:
            raise KeyError(f"Mock MCP has no handler for tool: {tool!r}")
        return self._handlers[tool](params)

    def calls_to(self, tool: str) -> list[dict[str, Any]]:
        return [p for t, p in self.calls if t == tool]

    # ---- canned defaults -------------------------------------------------
    def _register_default_handlers(self) -> None:
        self.register("get_state", lambda p: {
            "phase": "init",
            "lastCompletedPhase": "none",
        })
        self.register("get_projects_in_topological_order", lambda p: {
            "layers": [
                {"layer": 1, "projects": ["Core/Core.csproj"]},
                {"layer": 2, "projects": ["Data/Data.csproj"]},
                {"layer": 3, "projects": ["Web/Web.csproj"]},
            ],
        })
        self.register("convert_project_to_sdk_style", lambda p: {
            "project": p.get("project"),
            "converted": True,
            "warnings": [],
        })
        self.register("FindRecommendedPackageUpgrades", lambda p: {
            "upgrades": [
                {"id": "Newtonsoft.Json", "current": "11.0.0", "recommended": "13.0.3"},
            ],
        })
        self.register("ComputeDependencyLayers", lambda p: {
            "layers": [
                {"layer": 1, "projects": ["Core/Core.csproj"]},
                {"layer": 2, "projects": ["Data/Data.csproj"]},
                {"layer": 3, "projects": ["Web/Web.csproj"]},
            ],
        })


@pytest.fixture
def mock_mcp() -> MockMcp:
    return MockMcp()


# ---- Solution + feature dir fixtures ---------------------------------------

@pytest.fixture
def fake_solution_dir(tmp_path: Path, fixtures_dir: Path) -> Path:
    """Copy `tests/fixtures/fake-solution/` into a tmp dir; return its root."""
    dst = tmp_path / "fake-solution"
    shutil.copytree(fixtures_dir / "fake-solution", dst)
    return dst


@pytest.fixture
def feature_dir(tmp_path: Path) -> Path:
    """Active Spec Kit feature dir layout: `specs/<branch>/migration/`."""
    d = tmp_path / "specs" / "001-test-feature"
    (d / "migration").mkdir(parents=True)
    # Seed the canonical core artifacts so hooks resolve `{featureDir}` cleanly.
    (d / "spec.md").write_text("# Spec\n", encoding="utf-8")
    (d / "plan.md").write_text("# Plan\n", encoding="utf-8")
    (d / "tasks.md").write_text("# Tasks\n", encoding="utf-8")
    return d
