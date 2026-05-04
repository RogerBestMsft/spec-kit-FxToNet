"""T008: extension.yml schema, semver, file/script/hook resolution."""

from __future__ import annotations

from pathlib import Path

from ._helpers import SEMVER_RE, validate_with


def test_extension_yml_validates_against_schema(repo_root: Path, extension_yml: dict) -> None:
    validate_with(repo_root, "extension.schema.json", extension_yml)


def test_extension_version_is_semver(extension_yml: dict) -> None:
    assert SEMVER_RE.match(extension_yml["extension"]["version"])


def test_every_command_file_exists(extension_dir: Path, extension_yml: dict) -> None:
    missing: list[str] = []
    for cmd in extension_yml["provides"]["commands"]:
        target = extension_dir / cmd["file"]
        if not target.is_file():
            missing.append(f"{cmd['name']} -> {cmd['file']}")
    assert not missing, "Missing command files:\n  " + "\n  ".join(missing)


def test_every_command_script_exists(extension_dir: Path, extension_yml: dict) -> None:
    missing: list[str] = []
    for cmd in extension_yml["provides"]["commands"]:
        for script in cmd.get("scripts", []) or []:
            target = extension_dir / script
            if not target.is_file():
                missing.append(f"{cmd['name']} -> {script}")
    assert not missing, "Missing scripts:\n  " + "\n  ".join(missing)


def test_every_hook_command_is_declared(extension_yml: dict) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    hooks = extension_yml.get("hooks") or {}
    undeclared: list[str] = []
    for hook_name, hook in hooks.items():
        cmd = hook.get("command")
        if cmd not in declared:
            undeclared.append(f"{hook_name} -> {cmd}")
    assert not undeclared, "Undeclared hook commands:\n  " + "\n  ".join(undeclared)


def test_command_names_unique(extension_yml: dict) -> None:
    names = [c["name"] for c in extension_yml["provides"]["commands"]]
    dupes = [n for n in set(names) if names.count(n) > 1]
    assert not dupes, f"Duplicate command names: {dupes}"
