"""T029: orchestrate.md declares the documented per-layer migration phase order."""

from __future__ import annotations

from pathlib import Path

from ._driver import find_command, parse_command


# The canonical phase order documented in orchestrate.md. SDK conversion, package
# compatibility, version alignment, and multitarget migration are combined into a
# single per-layer migration phase.
EXPECTED_ORDER = [
    (1, "Initialize"),
    (2, "Run Assessment"),
    (3, "Create Migration Plan"),
    (4, "Per-Layer Migration"),
    (5, "Run ASP.NET Framework to ASP.NET Core Web Migration"),
    (6, "Completion"),
]


def test_orchestrate_phase_headings_present_and_in_order(extension_dir: Path) -> None:
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.orchestrate"))

    # `spec.sections` is a list of (n, title); take only the top-level workflow numbers.
    seen = [(n, title) for n, title in spec.sections if 1 <= n <= 8]
    assert seen, "no numbered top-level sections found in orchestrate.md"

    # Numbers must be strictly increasing.
    nums = [n for n, _ in seen]
    assert nums == sorted(nums), f"phase numbers not in order: {nums}"

    # Each expected phase title must appear (substring match).
    titles_lc = [t.lower() for _, t in seen]
    for _, expected_title in EXPECTED_ORDER:
        assert any(expected_title.lower() in t for t in titles_lc), (
            f"missing phase '{expected_title}' in orchestrate.md sections: {seen}"
        )


def test_orchestrate_marks_lastcompletedphase_for_each_milestone(extension_dir: Path) -> None:
    """Every major phase should write a `lastCompletedPhase: "<key>"` marker."""
    spec = parse_command(find_command(extension_dir, "speckit.fx-to-dotnet.orchestrate"))
    body = spec.body
    expected_keys = [
        "assessment",
        "layer-migration",
        "aspnet-migration",
    ]
    missing = [k for k in expected_keys if f'lastCompletedPhase: "{k}"' not in body]
    assert not missing, f"orchestrate.md missing lastCompletedPhase markers: {missing}"
