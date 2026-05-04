"""T010: workflow.yml schemas + step/command/input cross-references."""

from __future__ import annotations

import re
from pathlib import Path

from ._helpers import validate_with


INPUT_REF_RE = re.compile(r"\{\{\s*inputs\.([\w-]+)\s*\}\}")


def _walk_steps(steps: list[dict]):
    for step in steps:
        yield step
        if step.get("type") == "do-while":
            for nested in step.get("steps") or []:
                yield from _walk_steps([nested])


def test_each_workflow_validates_against_schema(
    repo_root: Path, workflow_ymls: list[tuple[Path, dict]]
) -> None:
    assert workflow_ymls, "No workflow.yml files discovered"
    for path, doc in workflow_ymls:
        try:
            validate_with(repo_root, "workflow.schema.json", doc)
        except Exception as exc:
            raise AssertionError(f"{path.name} failed schema: {exc}") from exc


def test_each_step_command_is_declared(
    workflow_ymls: list[tuple[Path, dict]], extension_yml: dict
) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    errors: list[str] = []
    for path, doc in workflow_ymls:
        for step in _walk_steps(doc.get("steps") or []):
            cmd = step.get("command")
            if cmd and cmd not in declared:
                errors.append(f"{path.name}::{step.get('id')} -> {cmd}")
    assert not errors, "Workflow step references undeclared commands:\n  " + "\n  ".join(errors)


def test_each_gate_has_options(workflow_ymls: list[tuple[Path, dict]]) -> None:
    errors: list[str] = []
    for path, doc in workflow_ymls:
        for step in _walk_steps(doc.get("steps") or []):
            if step.get("type") == "gate":
                opts = step.get("options") or []
                if not opts:
                    errors.append(f"{path.name}::{step.get('id')}")
    assert not errors, "Gate steps with empty/missing options:\n  " + "\n  ".join(errors)


def test_each_dowhile_has_condition_and_max_iterations(
    workflow_ymls: list[tuple[Path, dict]],
) -> None:
    errors: list[str] = []
    for path, doc in workflow_ymls:
        for step in _walk_steps(doc.get("steps") or []):
            if step.get("type") == "do-while":
                if not step.get("condition"):
                    errors.append(f"{path.name}::{step.get('id')} missing 'condition'")
                if not step.get("max_iterations"):
                    errors.append(f"{path.name}::{step.get('id')} missing 'max_iterations'")
    assert not errors, "do-while issues:\n  " + "\n  ".join(errors)


def test_input_references_resolve(workflow_ymls: list[tuple[Path, dict]]) -> None:
    errors: list[str] = []
    for path, doc in workflow_ymls:
        declared_inputs = set((doc.get("inputs") or {}).keys())
        # Scan all string values recursively for `{{ inputs.X }}` references.
        def _scan(node):
            if isinstance(node, str):
                for m in INPUT_REF_RE.finditer(node):
                    name = m.group(1)
                    if name not in declared_inputs:
                        errors.append(f"{path.name}: undeclared input '{name}'")
            elif isinstance(node, dict):
                for v in node.values():
                    _scan(v)
            elif isinstance(node, list):
                for v in node:
                    _scan(v)

        _scan(doc.get("steps"))
    assert not errors, "\n  ".join(["Undeclared input refs:"] + sorted(set(errors)))
