"""G2: PowerShell 5.1 compatibility lint for every .ps1 in the repo.

Windows PowerShell 5.1 is the lowest supported host. AI-authored PRs frequently emit
PowerShell 7-only syntax (`??`, `?:`, `ConvertFrom-Json -AsHashtable`). This test fails
fast on those constructs and on encoding that 5.1 cannot read (non-ASCII without a BOM).

Encoding rule (R3): a `.ps1` may be plain ASCII (no BOM required); any file containing
non-ASCII bytes MUST be UTF-8 with a BOM so Windows PowerShell 5.1 decodes it correctly.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest


UTF8_BOM = b"\xef\xbb\xbf"

# Forbidden PowerShell 7+ constructs (checked on code with comments/strings stripped
# heuristically by line). Patterns are intentionally conservative.
NULL_COALESCE_RE = re.compile(r"\?\?")          # ?? and ??=
TERNARY_RE = re.compile(r"\s\?\s.+\s:\s")        # `<cond> ? <a> : <b>`
ASHASHTABLE_RE = re.compile(r"ConvertFrom-Json\b[^\n]*-AsHashtable", re.IGNORECASE)


def _all_ps1(repo_root: Path) -> list[Path]:
    roots = [repo_root / "fx-to-dotnet" / "scripts", repo_root / "support_scripts"]
    files: list[Path] = []
    for root in roots:
        if root.is_dir():
            files.extend(p for p in root.glob("**/*.ps1") if p.is_file())
    return sorted(files)


def _ps1_files(repo_root: Path) -> list[Path]:
    files = _all_ps1(repo_root)
    if not files:
        pytest.skip("No .ps1 files found")
    return files


def test_no_null_coalescing_operator(repo_root: Path) -> None:
    bad: list[str] = []
    for p in _ps1_files(repo_root):
        text = p.read_text(encoding="utf-8-sig")
        for i, line in enumerate(text.splitlines(), 1):
            code = line.split("#", 1)[0]
            if NULL_COALESCE_RE.search(code):
                bad.append(f"{p.relative_to(repo_root)}:{i}: {line.strip()}")
    assert not bad, "PowerShell 7+ `??`/`??=` not allowed (PS 5.1):\n  " + "\n  ".join(bad)


def test_no_ternary_operator(repo_root: Path) -> None:
    bad: list[str] = []
    for p in _ps1_files(repo_root):
        text = p.read_text(encoding="utf-8-sig")
        for i, line in enumerate(text.splitlines(), 1):
            code = line.split("#", 1)[0]
            if TERNARY_RE.search(code):
                bad.append(f"{p.relative_to(repo_root)}:{i}: {line.strip()}")
    assert not bad, "PowerShell 7+ ternary `? :` not allowed (PS 5.1):\n  " + "\n  ".join(bad)


def test_no_convertfrom_json_ashashtable(repo_root: Path) -> None:
    bad: list[str] = []
    for p in _ps1_files(repo_root):
        text = p.read_text(encoding="utf-8-sig")
        if ASHASHTABLE_RE.search(text):
            bad.append(str(p.relative_to(repo_root)))
    assert not bad, (
        "`ConvertFrom-Json -AsHashtable` not available in PS 5.1:\n  " + "\n  ".join(bad)
    )


def test_encoding_is_ps51_safe(repo_root: Path) -> None:
    """ASCII files need no BOM; any non-ASCII .ps1 must be UTF-8 with a BOM."""
    bad: list[str] = []
    for p in _ps1_files(repo_root):
        raw = p.read_bytes()
        has_bom = raw.startswith(UTF8_BOM)
        body = raw[len(UTF8_BOM):] if has_bom else raw
        try:
            body.decode("ascii")
            is_ascii = True
        except UnicodeDecodeError:
            is_ascii = False
        if not is_ascii and not has_bom:
            bad.append(str(p.relative_to(repo_root)))
    assert not bad, (
        "Non-ASCII .ps1 must be saved UTF-8 with BOM for Windows PowerShell 5.1:\n  "
        + "\n  ".join(bad)
    )
