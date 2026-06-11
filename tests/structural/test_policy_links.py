"""T013: every policy/POLICY.md referenced from a command body exists.
T013b: every POLICY.md has valid discovery frontmatter (scope, applies-to, detection)."""

from __future__ import annotations

import re
from pathlib import Path

import yaml


POLICY_REF_RE = re.compile(r"policies/[\w./-]+?\.md")
FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)

VALID_SCOPES = {"core", "conditional"}
VALID_COMMANDS = {
    "assess",
    "plan",
    "multitarget",
    "build-fix",
    "web-migrate",
}


def test_every_referenced_policy_target_exists(extension_dir: Path) -> None:
    missing: list[str] = []
    for md in (extension_dir / "commands").glob("**/*.md"):
        text = md.read_text(encoding="utf-8")
        for m in POLICY_REF_RE.finditer(text):
            ref = m.group(0)
            target = extension_dir / ref
            if not target.is_file():
                missing.append(f"{md.relative_to(extension_dir)}: {ref}")
    assert not missing, "Unresolved policy references:\n  " + "\n  ".join(sorted(set(missing)))


def _policy_files(extension_dir: Path) -> list[Path]:
    """Return all domain policy POLICY.md files."""
    return sorted((extension_dir / "policies").glob("*/POLICY.md"))


def _parse_frontmatter(text: str) -> dict | None:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None
    return yaml.safe_load(m.group(1)) or {}


def test_every_policy_has_discovery_frontmatter(extension_dir: Path) -> None:
    """Every POLICY.md must have name, scope, and applies-to fields."""
    errors: list[str] = []
    for policy in _policy_files(extension_dir):
        rel = str(policy.relative_to(extension_dir))
        text = policy.read_text(encoding="utf-8")
        fm = _parse_frontmatter(text)
        if fm is None:
            errors.append(f"{rel}: missing YAML frontmatter")
            continue
        if "name" not in fm:
            errors.append(f"{rel}: missing 'name' field")
        if "scope" not in fm:
            errors.append(f"{rel}: missing 'scope' field")
        elif fm["scope"] not in VALID_SCOPES:
            errors.append(f"{rel}: scope '{fm['scope']}' not in {VALID_SCOPES}")
        if "applies-to" not in fm:
            errors.append(f"{rel}: missing 'applies-to' field")
        elif not isinstance(fm["applies-to"], list) or not fm["applies-to"]:
            errors.append(f"{rel}: 'applies-to' must be a non-empty list")
        else:
            bad = [c for c in fm["applies-to"] if c not in VALID_COMMANDS]
            if bad:
                errors.append(f"{rel}: unknown commands in applies-to: {bad}")
    assert not errors, "Policy frontmatter errors:\n  " + "\n  ".join(errors)


def test_conditional_policies_have_detection(extension_dir: Path) -> None:
    """Every conditional policy must have a detection section with triggers."""
    errors: list[str] = []
    for policy in _policy_files(extension_dir):
        rel = str(policy.relative_to(extension_dir))
        text = policy.read_text(encoding="utf-8")
        fm = _parse_frontmatter(text)
        if fm is None or fm.get("scope") != "conditional":
            continue
        detection = fm.get("detection")
        if not isinstance(detection, dict):
            errors.append(f"{rel}: conditional policy missing 'detection' mapping")
            continue
        has_trigger = any(
            isinstance(detection.get(k), list) and detection[k]
            for k in ("packages", "classifications", "code-patterns")
        )
        if not has_trigger:
            errors.append(
                f"{rel}: detection must have at least one non-empty trigger "
                f"(packages, classifications, or code-patterns)"
            )
    assert not errors, "Conditional policy detection errors:\n  " + "\n  ".join(errors)
