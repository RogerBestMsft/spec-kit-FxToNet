"""T009: preset.yml schema, version coupling, template resolution."""

from __future__ import annotations

import re
from pathlib import Path

from ._helpers import SEMVER_RE, validate_with


def test_preset_yml_validates_against_schema(repo_root: Path, preset_yml: dict) -> None:
    validate_with(repo_root, "preset.schema.json", preset_yml)


def test_preset_version_is_semver(preset_yml: dict) -> None:
    assert SEMVER_RE.match(preset_yml["preset"]["version"])


def _parse_constraint(spec: str) -> tuple[str, tuple[int, int, int]]:
    m = re.match(r"^\s*(>=|<=|==|>|<|~|\^)?\s*(\d+)\.(\d+)\.(\d+)", spec)
    assert m, f"Cannot parse version constraint: {spec!r}"
    op = m.group(1) or ">="
    return op, (int(m.group(2)), int(m.group(3)), int(m.group(4)))


def _parse_version(ver: str) -> tuple[int, int, int]:
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", ver)
    assert m, f"Cannot parse version: {ver!r}"
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def test_preset_extension_version_constraint_satisfied(
    preset_yml: dict, extension_yml: dict
) -> None:
    constraints = preset_yml.get("requires", {}).get("extensions") or []
    for c in constraints:
        if c["id"] != extension_yml["extension"]["id"]:
            continue
        op, required = _parse_constraint(c["version"])
        actual = _parse_version(extension_yml["extension"]["version"])
        if op == ">=":
            assert actual >= required, f"extension {actual} < required {required}"
        elif op == "==":
            assert actual == required, f"extension {actual} != required {required}"
        elif op == ">":
            assert actual > required, f"extension {actual} <= required {required}"
        elif op in ("<=", "<"):
            assert False, f"Unsupported upper-bound constraint in preset: {op}"


def test_every_template_path_exists(preset_dir: Path, preset_yml: dict) -> None:
    missing: list[str] = []
    for tpl in preset_yml.get("provides", {}).get("templates") or []:
        target = preset_dir / tpl["file"]
        if not target.is_file():
            missing.append(tpl["file"])
    assert not missing, "Missing preset templates:\n  " + "\n  ".join(missing)
