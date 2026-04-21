#!/usr/bin/env python3
"""Generate community catalog JSON entries from extension.yml files."""

import json
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

# Simple YAML value extractors (avoids pyyaml dependency for CI)
def _yaml_value(text: str, key: str) -> str | None:
    m = re.search(rf'^\s+{key}:\s*"?([^"\n]+?)"?\s*$', text, re.MULTILINE)
    return m.group(1).strip() if m else None


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    entries = []

    for ext_id in EXTENSIONS:
        yml = root / ext_id / "extension.yml"
        if not yml.exists():
            print(f"WARNING: {yml} not found", file=sys.stderr)
            continue

        text = yml.read_text(encoding="utf-8")
        version = _yaml_value(text, "version")
        name = _yaml_value(text, "name")
        description = _yaml_value(text, "description")
        author = _yaml_value(text, "author") or "Microsoft"
        repo = _yaml_value(text, "repository") or ""

        if not version:
            print(f"ERROR: no version in {yml}", file=sys.stderr)
            return 1

        entry = {
            "id": ext_id,
            "name": name or ext_id,
            "version": version,
            "description": description or "",
            "author": author,
            "url": f"{repo}/releases/download/v{version}/{ext_id}-{version}.zip",
            "repository": repo,
            "tags": ["dotnet", "migration", "modernization"],
            "family": "fx-to-dotnet",
        }
        entries.append(entry)

    json.dump(entries, sys.stdout, indent=2)
    print()  # trailing newline
    return 0


if __name__ == "__main__":
    sys.exit(main())
