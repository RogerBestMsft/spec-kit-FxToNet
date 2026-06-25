"""Documented migration task ordering includes prerequisites before MIG dispatch."""

from __future__ import annotations

from pathlib import Path

from ._driver import find_command, parse_command


def test_tasks_hook_documents_prerequisites_before_migration_tasks(
    extension_dir: Path,
) -> None:
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.tasks-hook"))
    body = spec.body.lower()

    prereq_idx = body.index("### prerequisites")
    mig_idx = body.index("### migration tasks")
    deps_idx = body.index("### dependencies")

    assert prereq_idx < mig_idx < deps_idx, (
        "tasks-hook should document prerequisites before MIG tasks and dependencies after them"
    )
    assert "must complete before migration dispatch begins" in body
    assert "dependency-safe" in body


def test_implement_hook_documents_prerequisite_deferral_before_mig_review(
    extension_dir: Path,
) -> None:
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.implement-hook"))
    body = spec.body.lower()

    parse_idx = body.index("## 4. parse the migration block")
    review_idx = body.index("## 5. per-task review loop")

    assert parse_idx < review_idx, "parse/deferral step should precede MIG review loop"
    assert "do not process any `[mig-*]` row on this invocation" in body
    assert "prerequisite tasks still remain" in body


def test_preset_implement_documents_segmented_execution_flow(extension_dir: Path) -> None:
    text = (extension_dir / "templates" / "commands" / "implement.md").read_text(
        encoding="utf-8"
    )
    lower = text.lower()

    branch_a_idx = lower.index("### branch a")
    branch_b_idx = lower.index("### branch b")
    branch_c_idx = lower.index("### branch c")

    assert branch_a_idx < branch_b_idx < branch_c_idx, (
        "preset implement flow should define Branch A (unresolved MIG) before Branch B (complete) before Branch C (no migration)"
    )
    assert "re-run `/speckit.implement`" in lower


def test_preset_implement_enforces_hard_stop_on_unresolved_migration(
    extension_dir: Path,
) -> None:
    text = (extension_dir / "templates" / "commands" / "implement.md").read_text(
        encoding="utf-8"
    )
    lower = text.lower()

    # Branch A must contain hard-stop language preventing [US*] execution
    assert "must not process any `[us*]` task on any pass where unresolved `[mig-*]` tasks exist" in lower, (
        "implement template must contain explicit prohibition against processing [US*] while [MIG-*] unresolved"
    )
    assert "must exit immediately" in lower, (
        "implement template must require EXIT after prerequisite execution when MIG tasks unresolved"
    )

    # Branch B must require the Migration Complete checkpoint as a mandatory gate
    assert "> ✓ migration complete" in lower, (
        "implement template must reference the Migration Complete checkpoint"
    )
    # The checkpoint must NOT be described as merely informational
    assert "you may treat it as informational" not in lower, (
        "implement template must NOT treat the migration checkpoint as merely informational"
    )
