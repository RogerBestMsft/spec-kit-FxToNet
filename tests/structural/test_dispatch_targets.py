"""G10: `[MIG-*]` dispatch trailers are well-formed and resolvable.

The `before_implement` hook is the only interpreter of `dispatch:` trailers and validates
each target against `^speckit\\.fx-to-dotnet\\.[a-z0-9-]+$`. This test guards that:
  1. `implement-hook.md` actually documents that validation regex, and
  2. every `dispatch:` target written in the project docs resolves to a declared command
     (and matches the namespace regex).
"""

from __future__ import annotations

import re
from pathlib import Path


# `dispatch: speckit.fx-to-dotnet.convert(ProjectA.csproj)` -> captures the command id.
DISPATCH_RE = re.compile(r"dispatch:\s*(speckit\.fx-to-dotnet\.[a-z0-9-]+)")
NAMESPACE_RE = re.compile(r"^speckit\.fx-to-dotnet\.[a-z0-9-]+$")
# The literal regex the hook must document (allowing escaped or unescaped dots).
DOC_REGEX_RE = re.compile(r"\^speckit\\?\.fx-to-dotnet\\?\.\[a-z0-9-\]\+\$")


def _doc_sources(extension_dir: Path, repo_root: Path) -> list[Path]:
    sources: list[Path] = []
    sources.extend((extension_dir / "commands").glob("**/*.md"))
    sources.extend((extension_dir / "templates").glob("**/*.md"))
    for readme in (repo_root / "README.md", extension_dir / "README.md"):
        if readme.is_file():
            sources.append(readme)
    return sorted(p for p in sources if p.is_file())


def test_implement_hook_documents_dispatch_regex(extension_dir: Path) -> None:
    hook = extension_dir / "commands" / "hooks" / "implement-hook.md"
    text = hook.read_text(encoding="utf-8")
    assert DOC_REGEX_RE.search(text), (
        "implement-hook.md must document the dispatch-target validation regex "
        r"`^speckit\.fx-to-dotnet\.[a-z0-9-]+$`"
    )


def test_dispatch_targets_resolve(extension_dir: Path, repo_root: Path, extension_yml: dict) -> None:
    declared = {c["name"] for c in extension_yml["provides"]["commands"]}
    errors: list[str] = []
    found = 0
    for md in _doc_sources(extension_dir, repo_root):
        text = md.read_text(encoding="utf-8")
        rel = md.relative_to(repo_root)
        for target in DISPATCH_RE.findall(text):
            found += 1
            if not NAMESPACE_RE.match(target):
                errors.append(f"{rel}: dispatch target '{target}' fails namespace regex")
            elif target not in declared:
                errors.append(f"{rel}: dispatch target '{target}' is not a declared command")
    assert found > 0, "Expected at least one documented dispatch: target"
    assert not errors, "Invalid dispatch targets:\n  " + "\n  ".join(sorted(set(errors)))
