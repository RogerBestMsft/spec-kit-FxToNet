"""Structural contract: tasks-hook.md documents kind-first sub-block sectioning.

The `after_tasks` hook must group emitted `[MIG-*]` tasks into four top-level
sub-blocks inside the `## Phase 1: .NET Framework Migration` block, emitted in
this fixed order:

  1. `### Solution-Wide (Baseline)`
  2. `### SDK-Style Conversion`   (rows nested under `#### Layer N`)
  3. `### Package Updates`        (rows nested under `#### Layer N`)
  4. `### Per-Project Migration`  (rows nested under `#### Project <path>`)

These tests assert the spec describes that contract and ships a worked example
so users can see the end result.
"""

from __future__ import annotations

import re
from pathlib import Path


HOOK_PATH = ("fx-to-dotnet", "commands", "hooks", "tasks-hook.md")

TOP_SUBBLOCKS = (
    "### Solution-Wide (Baseline)",
    "### SDK-Style Conversion",
    "### Package Updates",
    "### Per-Project Migration",
)


def _read_hook(extension_dir: Path) -> str:
    return (extension_dir / "commands" / "hooks" / "tasks-hook.md").read_text(
        encoding="utf-8"
    )


def test_contract_mentions_subblock_grouping(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    for heading in TOP_SUBBLOCKS:
        assert heading in body, (
            f"contract should reference the `{heading}` top-level sub-block"
        )
    assert "#### Layer N" in body, (
        "contract should reference nested `#### Layer N` subheadings inside SDK / Packages"
    )
    assert "#### Project <relative csproj path>" in body, (
        "contract should reference nested `#### Project <relative csproj path>` subheadings inside Per-Project Migration"
    )


def test_emit_step_describes_subblock_grouping(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    assert "Sub-block emission rules" in body, (
        "step 5 should contain a `Sub-block emission rules` section"
    )
    for heading in TOP_SUBBLOCKS:
        assert heading in body
    assert "(Layer N)" in body, (
        "step 5 should reference plan.md's `(Layer N)` annotations as the source of truth"
    )
    assert "globally sequential across all sub-blocks" in body, (
        "step 5 should state MIG numbering is globally sequential across sub-blocks"
    )


def test_validation_step_checks_subblock_structure(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    assert (
        "Every `[MIG-*]` row sits under exactly one of: `### Solution-Wide (Baseline)`,"
        in body
    )
    assert "strictly ascending order" in body, (
        "step 6 should require `#### Layer N` subheadings in strictly ascending order"
    )
    assert "in this exact order" in body, (
        "step 6 should require the four top-level sub-blocks in fixed order"
    )


def test_idempotency_rules_cover_subblock_headings(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    assert (
        "The four top-level sub-block headings (`### Solution-Wide (Baseline)`, `### SDK-Style Conversion`, `### Package Updates`, `### Per-Project Migration`)"
        in body
    )
    assert "Sub-block upgrade for legacy blocks" in body, (
        "step 2 should document a one-time in-place upgrade for legacy migration blocks"
    )


def test_worked_example_covers_all_subblocks(extension_dir: Path) -> None:
    body = _read_hook(extension_dir)
    assert "Worked end-to-end example" in body

    marker = "Worked end-to-end example"
    idx = body.find(marker)
    assert idx != -1
    tail = body[idx:]

    positions = []
    for heading in TOP_SUBBLOCKS:
        pos = tail.find(heading)
        assert pos != -1, f"worked example must contain `{heading}`"
        positions.append(pos)
    assert positions == sorted(positions), (
        "worked example must list the top-level sub-blocks in the documented order: "
        f"{TOP_SUBBLOCKS}"
    )

    for heading in ("#### Layer 1", "#### Layer 2", "#### Layer 3"):
        assert heading in tail, f"worked example must contain `{heading}`"

    assert re.search(r"^#### Project \S", tail, re.MULTILINE), (
        "worked example must contain at least one `#### Project <path>` heading"
    )

    mig_ids = [int(m) for m in re.findall(r"\[MIG-(\d{3})\]", tail)]
    assert mig_ids, "worked example must contain `[MIG-NNN]` rows"
    assert mig_ids == sorted(mig_ids), (
        f"worked example MIG IDs must be in ascending order; got {mig_ids}"
    )
    assert mig_ids == list(range(mig_ids[0], mig_ids[0] + len(mig_ids))), (
        f"worked example MIG IDs must be contiguous; got {mig_ids}"
    )

    dispatch_re = re.compile(
        r"^- \[ \] \[MIG-\d{3}\] \[P[0-3]\] .+ \u2014 dispatch: speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$"
    )
    for line in tail.splitlines():
        if line.startswith("- [ ] [MIG-"):
            assert dispatch_re.match(line), (
                f"worked example MIG row violates dispatch regex: {line!r}"
            )
