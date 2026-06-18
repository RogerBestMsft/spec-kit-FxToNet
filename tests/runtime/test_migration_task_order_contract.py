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

    prereq_idx = lower.index("## 2. execute prerequisite tasks ahead of migration")
    boundary_idx = lower.index("## 3. stop at unresolved migration boundary")
    us_idx = lower.index("## 4. execute user-story tasks")

    assert prereq_idx < boundary_idx < us_idx, (
        "preset implement flow should run prerequisites first, then stop at MIG boundary, then allow US tasks later"
    )
    assert "re-run `/speckit.implement` so the hook can process migration" in lower
