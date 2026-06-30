"""Supply-chain guard: GitHub Actions workflows may only use first-party actions.

Every ``uses:`` in ``.github/workflows/*.yml`` must reference either a local
workflow (``./...``) or an action owned by GitHub or Microsoft, and every remote
action must be pinned to a full 40-character commit SHA. This blocks third-party
actions and floating tags from entering the supply chain.
"""

from __future__ import annotations

import re
from pathlib import Path


# Owners considered first-party (GitHub or Microsoft). Compared case-insensitively.
ALLOWED_OWNERS = {"actions", "github", "microsoft", "azure"}

# Matches a step/job `uses:` line, capturing the reference (the rest of the line).
USES_RE = re.compile(r"^\s*(?:-\s*)?uses:\s*(\S+)")

# A full Git commit SHA (40 hex chars).
SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def _workflow_files(repo_root: Path) -> list[Path]:
    workflows_dir = repo_root / ".github" / "workflows"
    return sorted(workflows_dir.glob("*.yml")) + sorted(workflows_dir.glob("*.yaml"))


def _iter_uses(repo_root: Path):
    """Yield (file, line_number, reference) for every `uses:` in the workflows."""
    for path in _workflow_files(repo_root):
        for lineno, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            match = USES_RE.match(line)
            if match:
                yield path, lineno, match.group(1).strip().strip("'\"")


def test_workflows_exist(repo_root: Path) -> None:
    assert _workflow_files(repo_root), "No workflow files found under .github/workflows/."


def test_only_first_party_actions(repo_root: Path) -> None:
    """No third-party actions: every remote `uses:` owner must be GitHub or Microsoft."""
    violations: list[str] = []
    for path, lineno, ref in _iter_uses(repo_root):
        # Local reusable workflows (./.github/workflows/...) are always allowed.
        if ref.startswith("./") or ref.startswith("../"):
            continue
        owner = ref.split("/", 1)[0]
        if owner.lower() not in ALLOWED_OWNERS:
            rel = path.relative_to(repo_root).as_posix()
            violations.append(f"{rel}:{lineno} uses third-party action '{ref}'")

    assert not violations, (
        "Only GitHub/Microsoft-owned actions are allowed "
        f"(owners: {', '.join(sorted(ALLOWED_OWNERS))}). Offending uses:\n  "
        + "\n  ".join(violations)
        + "\nReplace these with a first-party action or the GitHub CLI (gh)."
    )


def test_remote_actions_are_sha_pinned(repo_root: Path) -> None:
    """Every remote action must be pinned to a full 40-character commit SHA."""
    violations: list[str] = []
    for path, lineno, ref in _iter_uses(repo_root):
        if ref.startswith("./") or ref.startswith("../"):
            continue
        # `owner/repo@ref` or `owner/repo/path@ref`.
        if "@" not in ref:
            rel = path.relative_to(repo_root).as_posix()
            violations.append(f"{rel}:{lineno} '{ref}' is not pinned (no @ref)")
            continue
        git_ref = ref.rsplit("@", 1)[1]
        if not SHA_RE.match(git_ref):
            rel = path.relative_to(repo_root).as_posix()
            violations.append(
                f"{rel}:{lineno} '{ref}' is pinned to '{git_ref}', not a 40-char commit SHA"
            )

    assert not violations, (
        "Remote actions must be pinned to a full commit SHA (a `# vN` comment may "
        "follow). Offending uses:\n  " + "\n  ".join(violations)
    )
