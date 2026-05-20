"""Structural contract: tasks-hook.md documents layer-based visual sectioning.

The `after_tasks` hook must group emitted `[MIG-*]` tasks under `### Layer N`
subheadings (with a trailing `### Solution-Wide` bucket for solution-scope
tasks) inside the `## Phase 1: .NET Framework Migration` block. These tests
assert the spec describes that contract and ships a worked example so users
can see the end result.
"""

from __future__ import annotations

import re
from pathlib import Path


HOOK_PATH = ("fx-to-dotnet", "commands", "hooks", "tasks-hook.md")


def _read_hook(extension_dir: Path) -> str:
    return (extension_dir / "commands" / "hooks" / "tasks-hook.md").read_text(
        encoding="utf-8"
    )


def test_contract_mentions_layer_grouping(extension_dir: Path) -> None:
    body = _read_hook(extension_dir).lower()
    assert "### layer n" in body, "contract should reference `### Layer N` subheadings"
    assert "### solution-wide" in body, (
        "contract should reference the `### Solution-Wide` bucket for solution-scope tasks"
    )


def test_emit_step_describes_layer_grouping(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    # The emit step (step 5) must describe grouping under `### Layer N` subheadings.
    assert "grouped under `### Layer N`" in body, (
        "step 5 should instruct the hook to group MIG rows under `### Layer N` subheadings"
    )
    # Must explain where the layer number comes from.
    assert "(Layer N)" in body, (
        "step 5 should reference plan.md's `(Layer N)` annotations as the source of truth"
    )
    # Global numbering must be preserved across layer boundaries.
    assert "globally sequential across all layers" in body, (
        "step 5 should state MIG numbering is globally sequential across layers"
    )


def test_validation_step_checks_layer_structure(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    # Step 6 must validate that every MIG row sits under a layer or solution-wide heading.
    assert "Every `[MIG-*]` row sits under either a `### Layer N` heading or the trailing `### Solution-Wide` heading" in body
    assert "strictly ascending order" in body, (
        "step 6 should require layer subheadings in strictly ascending order"
    )


def test_idempotency_rules_cover_layer_subheadings(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    # The idempotency block must call out the layer subheadings as extension-managed.
    assert (
        "`### Layer N` and `### Solution-Wide` subheadings inside the migration block are part of the extension-managed block"
        in body
    )
    # Legacy upgrade path must be documented in step 2.
    assert "Layer-heading upgrade for legacy blocks" in body, (
        "step 2 should document a one-time in-place upgrade for legacy migration blocks"
    )


def test_worked_example_is_present_and_shows_multiple_layers(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    # The end-to-end example block lives in step 5.
    assert "Worked end-to-end example" in body

    # Locate the fenced code block that follows the "Worked end-to-end example" marker
    # and contains the layer subheadings.
    marker = "Worked end-to-end example"
    idx = body.find(marker)
    assert idx != -1
    tail = body[idx:]

    # The example must show at least Layer 1, Layer 2, Layer 3, and Solution-Wide.
    for heading in ("### Layer 1", "### Layer 2", "### Layer 3", "### Solution-Wide"):
        assert heading in tail, f"worked example must contain `{heading}`"

    # MIG IDs in the example must be strictly ascending and zero-padded 3 digits.
    mig_ids = [int(m) for m in re.findall(r"\[MIG-(\d{3})\]", tail)]
    assert mig_ids, "worked example must contain `[MIG-NNN]` rows"
    assert mig_ids == sorted(mig_ids), (
        f"worked example MIG IDs must be in ascending order; got {mig_ids}"
    )
    assert mig_ids == list(range(mig_ids[0], mig_ids[0] + len(mig_ids))), (
        f"worked example MIG IDs must be contiguous; got {mig_ids}"
    )

    # Every MIG row in the example must satisfy the documented dispatch regex.
    dispatch_re = re.compile(
        r"^- \[ \] \[MIG-\d{3}\] \[P[0-3]\] .+ \u2014 dispatch: speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$"
    )
    for line in tail.splitlines():
        if line.startswith("- [ ] [MIG-"):
            assert dispatch_re.match(line), (
                f"worked example MIG row violates dispatch regex: {line!r}"
            )
