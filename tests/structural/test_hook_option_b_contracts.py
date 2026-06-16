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
    assert "normalize prose references to phases" in lower
