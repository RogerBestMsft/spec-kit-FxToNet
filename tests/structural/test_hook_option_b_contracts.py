"""T032: Option B hook contracts are encoded in command docs and manifest."""

from __future__ import annotations

from pathlib import Path


def test_after_specify_hook_is_registered_and_mandatory(extension_yml: dict) -> None:
    hooks = extension_yml.get("hooks") or {}
    assert "after_specify" in hooks, "after_specify hook slot missing"
    assert hooks["after_specify"]["command"] == "speckit.fx-to-dotnet.specify-hook"
    assert hooks["after_specify"].get("optional", False) is False


def test_plan_hook_documents_fail_fast_strictness(extension_dir: Path) -> None:
    text = (extension_dir / "commands" / "hooks" / "plan-hook.md").read_text(
        encoding="utf-8"
    )
    lower = text.lower()
    assert "plan strictness is fail-fast" in lower
    assert "competing migration content found outside" in lower


def test_tasks_hook_documents_path_overlap_dedupe(extension_dir: Path) -> None:
    text = (extension_dir / "commands" / "hooks" / "tasks-hook.md").read_text(
        encoding="utf-8"
    )
    lower = text.lower()
    assert "dedupe strictness uses option b" in lower
    assert "path-overlap conflict" in lower
    assert "### prerequisites" in lower
    assert "must run before migration dispatch begins" in lower
    assert "migration-task emission order is explicit and dependency-safe" in lower
    assert "normalize prose references to phases" in lower
    assert "replace the extension-managed placeholder" in lower
    assert "phase 1: .net framework migration" in lower


def test_tasks_template_documents_placeholder_replacement(extension_dir: Path) -> None:
    text = (extension_dir / "templates" / "commands" / "tasks.md").read_text(
        encoding="utf-8"
    )
    lower = text.lower()
    assert "extension-managed placeholder" in lower
    assert "phase 1: .net framework migration (extension-managed placeholder)" in lower
    assert "replace this heading with the populated `## phase 1: .net framework migration` block" in lower
    assert "### prerequisites" in lower
    assert "renumber the following user-story phases" in lower


def test_implement_template_documents_prerequisite_boundary(extension_dir: Path) -> None:
    text = (extension_dir / "templates" / "commands" / "implement.md").read_text(
        encoding="utf-8"
    )
    lower = text.lower()
    assert "execute prerequisite tasks ahead of migration" in lower
    assert "stop at unresolved migration boundary" in lower
    assert "re-run `/speckit.implement` so the hook can process migration" in lower
