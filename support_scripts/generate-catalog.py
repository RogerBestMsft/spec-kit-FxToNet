#!/usr/bin/env python3
"""Generate community catalog JSON entries from extension.yml and preset.yml files.

Outputs a single JSON object:
  { "extensions": [ { ...entry... } ], "presets": [ { ...entry... } ] }

Both entries reference the same combined release artifact:
  {repository}/releases/download/v{version}/fx-to-dotnet-{version}.zip
"""

import json
import re
import sys
from pathlib import Path

EXTENSIONS = [
    "fx-to-dotnet",
]

PRESETS = [
    "fx-to-dotnet-sdd",
]

# Simple YAML value extractors (avoids pyyaml dependency for CI)
def _yaml_value(text: str, key: str) -> str | None:
    m = re.search(rf'^\s+{key}:\s*"?([^"\n]+?)"?\s*$', text, re.MULTILINE)
    return m.group(1).strip() if m else None


def _build_entry(
    artifact_id: str,
    text: str,
    family: str,
    default_tags: list[str],
    bundle_id: str,
) -> dict | None:
    version = _yaml_value(text, "version")
    if not version:
        print(f"ERROR: no version for {artifact_id}", file=sys.stderr)
        return None
    repo = _yaml_value(text, "repository") or ""
    return {
        "id": artifact_id,
        "name": _yaml_value(text, "name") or artifact_id,
        "version": version,
        "description": _yaml_value(text, "description") or "",
        "author": _yaml_value(text, "author") or "Microsoft",
        # Both extension and preset entries reference the single combined bundle zip.
        "url": f"{repo}/releases/download/v{version}/{bundle_id}-{version}.zip",
        "repository": repo,
        "tags": default_tags,
        "family": family,
        "verified": False,
    }


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    bundle_id = "fx-to-dotnet"  # name of the single combined release zip
    out: dict[str, list[dict]] = {"extensions": [], "presets": []}
    errors = 0

    for ext_id in EXTENSIONS:
        yml = root / ext_id / "extension.yml"
        if not yml.exists():
            print(f"WARNING: {yml} not found", file=sys.stderr)
            continue
        entry = _build_entry(
            ext_id,
            yml.read_text(encoding="utf-8"),
            family="fx-to-dotnet",
            default_tags=["dotnet", "migration", "modernization"],
            bundle_id=bundle_id,
        )
        if entry is None:
            errors += 1
            continue
        out["extensions"].append(entry)

    for preset_id in PRESETS:
        yml = root / "presets" / preset_id / "preset.yml"
        if not yml.exists():
            print(f"WARNING: {yml} not found", file=sys.stderr)
            continue
        entry = _build_entry(
            preset_id,
            yml.read_text(encoding="utf-8"),
            family="fx-to-dotnet",
            default_tags=["dotnet", "migration", "sdd", "preset"],
            bundle_id=bundle_id,
        )
        if entry is None:
            errors += 1
            continue
        out["presets"].append(entry)

    if errors:
        return 1

    json.dump(out, sys.stdout, indent=2)
    print()  # trailing newline
    return 0


if __name__ == "__main__":
    sys.exit(main())
