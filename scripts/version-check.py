#!/usr/bin/env python3
"""Verify all spec-kit extensions declare the same version."""

import sys
import re
from pathlib import Path

EXTENSIONS = [
    "fx-to-dotnet",
]

VERSION_RE = re.compile(r'^\s+version:\s*"?([^"\s]+)"?\s*$', re.MULTILINE)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    versions: dict[str, str] = {}
    errors = 0

    for ext in EXTENSIONS:
        yml = root / ext / "extension.yml"
        if not yml.exists():
            print(f"ERROR: {yml} not found")
            errors += 1
            continue
        m = VERSION_RE.search(yml.read_text(encoding="utf-8"))
        if not m:
            print(f"ERROR: no version field in {yml}")
            errors += 1
            continue
        versions[ext] = m.group(1)

    if errors:
        return 1

    unique = set(versions.values())
    if len(unique) != 1:
        print("ERROR: version mismatch across extensions:")
        for ext, ver in sorted(versions.items()):
            print(f"  {ext}: {ver}")
        return 1

    version = unique.pop()
    print(f"OK: all {len(EXTENSIONS)} extensions at version {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
