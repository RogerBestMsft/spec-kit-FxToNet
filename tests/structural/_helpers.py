"""Shared helpers for structural tests."""

from __future__ import annotations

import json
import re
from pathlib import Path

import jsonschema


SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$")


def load_schema(repo_root: Path, name: str) -> dict:
    return json.loads((repo_root / "tests" / "schemas" / name).read_text(encoding="utf-8"))


def validate_with(repo_root: Path, schema_name: str, data: dict) -> None:
    schema = load_schema(repo_root, schema_name)
    jsonschema.validate(instance=data, schema=schema)
