#!/usr/bin/env python3
"""Generate community catalog JSON entries from extension.yml and preset.yml files.

Outputs a single JSON object:
  { "extensions": [ { ...entry... } ], "presets": [ { ...entry... } ] }

The extension and the companion preset now ship together inside the single
`fx-to-dotnet.zip` bundle (both `extension.yml` and `preset.yml`
live under the `fx-to-dotnet/` subfolder). Both catalog entries reference
the same combined artifact:
  {repository}/releases/download/v{version}/fx-to-dotnet.zip
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
    artifact_zip: str,
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
        "url": f"{repo}/releases/download/v{version}/{artifact_zip}.zip",
        "repository": repo,
        "tags": default_tags,
        "family": family,
        "verified": False,
    }


def main() -> int:
    root = Path(__file__).resolve().parent.parent
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
            # combined bundle (extension + preset together)
            artifact_zip=ext_id,
        )
        if entry is None:
            errors += 1
            continue
        out["extensions"].append(entry)

    for preset_id in PRESETS:
        # The preset now ships alongside the extension under fx-to-dotnet/.
        yml = root / "fx-to-dotnet" / "preset.yml"
        if not yml.exists():
            print(f"WARNING: {yml} not found", file=sys.stderr)
            continue
        entry = _build_entry(
            preset_id,
            yml.read_text(encoding="utf-8"),
            family="fx-to-dotnet",
            default_tags=["dotnet", "migration", "sdd", "preset"],
            # combined bundle (same zip as the extension)
            artifact_zip="fx-to-dotnet",
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
