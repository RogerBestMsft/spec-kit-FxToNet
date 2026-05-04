"""T031: hook lifecycle — mandatory hooks fail-loud, optional silent-exit."""

from __future__ import annotations

from pathlib import Path

from ._driver import find_command, parse_command


HOOK_NAMES = {
    "after_specify": "speckit.fx-to-dotnet.specify-hook",
    "after_plan": "speckit.fx-to-dotnet.plan-hook",
    "after_tasks": "speckit.fx-to-dotnet.tasks-hook",
    "before_implement": "speckit.fx-to-dotnet.implement-hook",
    "after_implement": "speckit.fx-to-dotnet.verify-hook",
}


def test_all_lifecycle_hooks_declared_and_resolvable(extension_yml: dict) -> None:
    hooks = extension_yml.get("hooks") or {}
    for slot, expected_cmd in HOOK_NAMES.items():
        assert slot in hooks, f"missing hook slot: {slot}"
        assert hooks[slot]["command"] == expected_cmd


def test_mandatory_vs_optional_classification(extension_yml: dict) -> None:
    hooks = extension_yml["hooks"]
    # before_implement is THE gate — must be mandatory.
    assert hooks["before_implement"].get("optional", False) is False
    # after_specify, after_plan, after_tasks are mandatory in v0.7.0.
    for slot in ("after_specify", "after_plan", "after_tasks"):
        assert hooks[slot].get("optional", False) is False, (
            f"{slot} should be mandatory in v0.7.0"
        )
    # after_implement (verify) is optional.
    assert hooks["after_implement"].get("optional", False) is True


def test_each_hook_command_file_exists(extension_dir: Path) -> None:
    for cmd_name in HOOK_NAMES.values():
        path = find_command(extension_dir, cmd_name)
        assert path.is_file(), f"missing hook file: {path}"


def test_each_hook_documents_silent_exit_on_no_framework(extension_dir: Path) -> None:
    """Optional hooks AND mandatory hooks both silent-exit when no Framework
    project is detected. The plan in implement-hook is the only one that does
    a precondition check (and fails-loud only on missing migration artifacts
    *after* detection succeeds)."""
    for cmd_name in HOOK_NAMES.values():
        spec = parse_command(find_command(extension_dir, cmd_name))
        body = spec.body.lower()
        assert "silent-exit" in body or "silent exit" in body, (
            f"{cmd_name} markdown does not document silent-exit behavior"
        )


def test_implement_hook_documents_precondition_failure(extension_dir: Path) -> None:
    """The before_implement gate must fail-loud on missing analysis/plan/[MIG] tasks."""
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.implement-hook"))
    body = spec.body.lower()
    # Look for any of the documented precondition markers.
    assert any(marker in body for marker in ("precondition", "preconditions", "exit non-zero", "exit 1")), (
        "implement-hook should document fail-loud precondition behavior"
    )
