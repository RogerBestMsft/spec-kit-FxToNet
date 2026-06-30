"""Structural validation for GitHub Actions workflows (first-party, no network).

This is the in-repo, dependency-free alternative to an external workflow linter:
it parses every ``.github/workflows/*.yml`` with PyYAML (already a test dependency)
and asserts the structural invariants that catch the common mistakes -- missing
triggers, jobs without a runner, and steps that are neither an action nor a script.

The companion ``test_workflow_actions.py`` enforces the supply-chain rules
(first-party owners + SHA pinning); this module enforces shape.
"""

from __future__ import annotations

from pathlib import Path

import yaml


# PyYAML (YAML 1.1) parses the bare ``on:`` key as the boolean ``True``. Accept
# either spelling so the trigger check works regardless of how it was written.
_ON_KEYS = ("on", True)


def _workflow_files(repo_root: Path) -> list[Path]:
    workflows_dir = repo_root / ".github" / "workflows"
    return sorted(workflows_dir.glob("*.yml")) + sorted(workflows_dir.glob("*.yaml"))


def _load(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    assert isinstance(data, dict), f"{path.name}: workflow is not a YAML mapping"
    return data


def _has_trigger(data: dict) -> bool:
    return any(key in data for key in _ON_KEYS)


def test_workflows_parse_and_have_triggers(repo_root: Path) -> None:
    """Every workflow parses as a mapping with `on:` triggers and a `jobs:` map."""
    for path in _workflow_files(repo_root):
        data = _load(path)
        assert _has_trigger(data), f"{path.name}: missing top-level 'on:' triggers"
        jobs = data.get("jobs")
        assert isinstance(jobs, dict) and jobs, (
            f"{path.name}: missing or empty 'jobs:' mapping"
        )


def test_jobs_have_runner_or_reusable_workflow(repo_root: Path) -> None:
    """Each job must define `runs-on` or call a reusable workflow via `uses`."""
    violations: list[str] = []
    for path in _workflow_files(repo_root):
        for job_id, job in _load(path).get("jobs", {}).items():
            if not isinstance(job, dict):
                violations.append(f"{path.name}:{job_id} is not a mapping")
                continue
            if "runs-on" not in job and "uses" not in job:
                violations.append(
                    f"{path.name}:{job_id} has neither 'runs-on' nor a reusable 'uses'"
                )
    assert not violations, "Malformed jobs:\n  " + "\n  ".join(violations)


def test_steps_are_action_xor_script(repo_root: Path) -> None:
    """Each step must have exactly one of `uses:` (action) or `run:` (script)."""
    violations: list[str] = []
    for path in _workflow_files(repo_root):
        for job_id, job in _load(path).get("jobs", {}).items():
            if not isinstance(job, dict):
                continue
            for idx, step in enumerate(job.get("steps", []) or []):
                if not isinstance(step, dict):
                    violations.append(f"{path.name}:{job_id} step #{idx} is not a mapping")
                    continue
                has_uses = "uses" in step
                has_run = "run" in step
                if has_uses == has_run:  # both or neither
                    label = step.get("name", f"#{idx}")
                    violations.append(
                        f"{path.name}:{job_id} step '{label}' must have exactly one "
                        "of 'uses' or 'run'"
                    )
    assert not violations, "Malformed steps:\n  " + "\n  ".join(violations)
