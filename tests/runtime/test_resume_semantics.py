"""T030: pre-seeded `lastCompletedPhase` makes the orchestrator skip earlier phases."""

from __future__ import annotations

from pathlib import Path

from ._driver import read_orchestration, write_orchestration


# Documented phase order in orchestrate.md `lastCompletedPhase` values.
PHASE_ORDER = [
    "none",
    "assessment",
    "sdk-normalization",
    "package-compat",
    "multitarget",
    "aspnet-migration",
]


def _phases_remaining_after(last_completed: str) -> list[str]:
    """Pure simulator: which phases remain after `last_completed`?"""
    idx = PHASE_ORDER.index(last_completed)
    return PHASE_ORDER[idx + 1:]


def test_resume_skips_already_completed_phases(feature_dir: Path) -> None:
    sln = feature_dir / "FakeSolution.sln"
    write_orchestration(feature_dir, solution=sln, last_completed_phase="assessment")

    state = read_orchestration(feature_dir)
    assert state["lastCompletedPhase"] == "assessment"

    remaining = _phases_remaining_after(state["lastCompletedPhase"])
    assert "assessment" not in remaining
    assert remaining[0] == "sdk-normalization"


def test_fresh_orchestration_runs_all_phases(feature_dir: Path) -> None:
    sln = feature_dir / "FakeSolution.sln"
    write_orchestration(feature_dir, solution=sln, last_completed_phase="none")

    state = read_orchestration(feature_dir)
    remaining = _phases_remaining_after(state["lastCompletedPhase"])
    assert remaining[0] == "assessment"
    assert remaining[-1] == "aspnet-migration"


def test_completed_orchestration_has_no_remaining_phases(feature_dir: Path) -> None:
    sln = feature_dir / "FakeSolution.sln"
    write_orchestration(feature_dir, solution=sln, last_completed_phase="aspnet-migration")
    state = read_orchestration(feature_dir)
    assert _phases_remaining_after(state["lastCompletedPhase"]) == []
