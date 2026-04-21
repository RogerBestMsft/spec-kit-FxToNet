#!/usr/bin/env python3
"""Verify all cross-extension command references resolve to declared commands."""

import re
import sys
from pathlib import Path

EXTENSIONS = [
    "fx-to-dotnet",
    "fx-to-dotnet-assess",
    "fx-to-dotnet-plan",
    "fx-to-dotnet-sdk-convert",
    "fx-to-dotnet-build-fix",
    "fx-to-dotnet-package-compat",
    "fx-to-dotnet-multitarget",
    "fx-to-dotnet-web-migrate",
    "fx-to-dotnet-detect-project",
    "fx-to-dotnet-route-inventory",
    "fx-to-dotnet-policies",
]

VERSION_RE = re.compile(r'^\s+version:\s*"?([^"\s]+)"?\s*$', re.MULTILINE)
COMMAND_NAME_RE = re.compile(r'^\s+-\s*name:\s*"?([^"\s]+)"?\s*$', re.MULTILINE)
CROSS_REF_RE = re.compile(r'speckit\.fx-to-dotnet[\w-]*\.\w+')


def collect_declared_commands(root: Path) -> set[str]:
    commands: set[str] = set()
    for ext in EXTENSIONS:
        yml = root / ext / "extension.yml"
        if not yml.exists():
            continue
        text = yml.read_text(encoding="utf-8")
        for m in COMMAND_NAME_RE.finditer(text):
            commands.add(m.group(1))
    return commands


def audit_references(root: Path, declared: set[str]) -> list[str]:
    errors: list[str] = []
    for ext in EXTENSIONS:
        commands_dir = root / ext / "commands"
        if not commands_dir.is_dir():
            continue
        for md in commands_dir.glob("*.md"):
            text = md.read_text(encoding="utf-8")
            for m in CROSS_REF_RE.finditer(text):
                ref = m.group(0)
                if ref not in declared:
                    rel = md.relative_to(root.parent)
                    errors.append(f"{rel}: unresolved reference '{ref}'")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    declared = collect_declared_commands(root)

    if not declared:
        print("ERROR: no commands found in any extension.yml")
        return 1

    print(f"Found {len(declared)} declared commands")
    errors = audit_references(root, declared)

    if errors:
        print(f"\n{len(errors)} unresolved cross-references:")
        for e in errors:
            print(f"  {e}")
        return 1

    print("OK: all cross-extension references resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
