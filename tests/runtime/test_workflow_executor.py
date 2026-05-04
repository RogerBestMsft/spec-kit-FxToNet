"""T032: minimal workflow.yml interpreter executes assess-and-plan + sdk-normalize."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from .conftest import MockMcp


class WorkflowExecutor:
    """Minimal interpreter for the steps subset used by fx-to-dotnet workflows."""

    def __init__(self, workflow: dict, mock_mcp: MockMcp) -> None:
        self.workflow = workflow
        self.mock = mock_mcp
        self.trace: list[dict[str, Any]] = []
        self.gate_responses: dict[str, str] = {}

    def respond_to_gate(self, step_id: str, choice: str) -> None:
        self.gate_responses[step_id] = choice

    def run(self, inputs: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        inputs = inputs or {}
        self._run_steps(self.workflow.get("steps") or [], inputs)
        return self.trace

    def _run_steps(self, steps: list[dict], inputs: dict) -> None:
        for step in steps:
            kind = step.get("type", "command")
            if kind == "command" or step.get("command"):
                self._run_command(step, inputs)
            elif kind == "gate":
                self._run_gate(step)
            elif kind == "do-while":
                self._run_do_while(step, inputs)
            else:
                raise NotImplementedError(f"unsupported step kind: {kind}")

    def _run_command(self, step: dict, inputs: dict) -> None:
        # In the executor smoke-test we simply translate the command name into
        # a representative MCP call so the trace captures the dispatch.
        self.trace.append({"step": step["id"], "command": step["command"]})
        # Side-effect: each command would invoke at least one MCP tool;
        # we surface the dispatch so the mock records it.
        if "assess" in step["command"]:
            self.mock.call("FindRecommendedPackageUpgrades", {"step": step["id"]})
        elif "convert" in step["command"]:
            self.mock.call("convert_project_to_sdk_style", {"step": step["id"]})
        elif "fix" in step["command"]:
            self.mock.call("get_state", {"step": step["id"]})
        elif "detect" in step["command"]:
            self.mock.call("get_projects_in_topological_order", {"step": step["id"]})

    def _run_gate(self, step: dict) -> None:
        choice = self.gate_responses.get(step["id"])
        if choice is None:
            # Default to the first option so workflows complete deterministically.
            choice = step["options"][0]
        self.trace.append({"step": step["id"], "gate": True, "choice": choice})
        if choice == "reject" and step.get("on_reject") == "abort":
            raise RuntimeError(f"gate {step['id']} rejected -> abort")

    def _run_do_while(self, step: dict, inputs: dict) -> None:
        max_iter = step["max_iterations"]
        for i in range(max_iter):
            self._run_steps(step.get("steps") or [], inputs)
            # Look at the most recent gate inside the loop to decide continuation.
            inner_gates = [t for t in self.trace if t.get("gate") and t["step"].endswith("gate")]
            last = inner_gates[-1] if inner_gates else None
            if last is None or last["choice"] != "continue":
                break


def _load(path: Path) -> dict:
    import yaml
    return yaml.safe_load(path.read_text(encoding="utf-8"))


@pytest.fixture
def assess_and_plan_workflow(extension_dir: Path) -> dict:
    return _load(extension_dir / "commands" / "workflows" / "assess-and-plan" / "workflow.yml")


@pytest.fixture
def sdk_normalize_workflow(extension_dir: Path) -> dict:
    return _load(extension_dir / "commands" / "workflows" / "sdk-normalize" / "workflow.yml")


def test_assess_and_plan_completes(assess_and_plan_workflow: dict, mock_mcp: MockMcp) -> None:
    ex = WorkflowExecutor(assess_and_plan_workflow, mock_mcp)
    trace = ex.run({"solution": "FakeSolution.sln"})
    assert trace, "executor produced no trace"
    # At least one assess-related dispatch happened.
    assert any("assess" in (t.get("command") or "") for t in trace)


def test_sdk_normalize_runs_one_layer_then_done(
    sdk_normalize_workflow: dict, mock_mcp: MockMcp
) -> None:
    ex = WorkflowExecutor(sdk_normalize_workflow, mock_mcp)
    # Simulate the user choosing 'done' after the first layer-gate completes.
    ex.respond_to_gate("layer-gate", "done")
    ex.respond_to_gate("review-normalize", "approve")
    trace = ex.run({"solution": "FakeSolution.sln"})

    convert_steps = [t for t in trace if t.get("command", "").endswith(".convert")]
    fix_steps = [t for t in trace if t.get("command", "").endswith(".fix")]
    assert len(convert_steps) >= 1
    assert len(fix_steps) >= 1
    # Sanity: MCP recorded the convert + fix dispatches.
    assert mock_mcp.calls_to("convert_project_to_sdk_style")


def test_sdk_normalize_aborts_on_layer_gate_reject(
    sdk_normalize_workflow: dict, mock_mcp: MockMcp
) -> None:
    ex = WorkflowExecutor(sdk_normalize_workflow, mock_mcp)
    ex.respond_to_gate("layer-gate", "reject")
    with pytest.raises(RuntimeError, match="abort"):
        ex.run({"solution": "FakeSolution.sln"})
