<!--
Thanks for contributing to fx-to-dotnet! Keep changes within scope:
docs / markdown / YAML / scripts / tests only — no build system, app code, or new runtime deps.
See CONTRIBUTING.md and .github/copilot-instructions.md.
-->

## Summary

<!-- What does this PR change and why? Link the issue it closes. -->

Closes #

## Type of change

- [ ] Command or hook (`fx-to-dotnet/commands/**`)
- [ ] Policy (`fx-to-dotnet/policies/**`)
- [ ] Script (`fx-to-dotnet/scripts/**` or `support_scripts/**`)
- [ ] Manifest / preset / version
- [ ] Tests
- [ ] Docs only

## Validation (mirrors CI)

- [ ] `python support_scripts/version-check.py`
- [ ] `python support_scripts/cross-reference-audit.py`
- [ ] `pwsh support_scripts/mcp-config-validate.ps1` (or `bash support_scripts/mcp-config-validate.sh`)
- [ ] `pytest tests/structural tests/scripts`
- [ ] `pytest tests/runtime` (if commands/hooks/orchestrator changed)

## Conventions checklist

- [ ] Version is identical across `extension.yml`, `preset.yml`, and `README.md` (bumped via `support_scripts/bump-version.*`, not by hand).
- [ ] New/renamed commands are declared in `extension.yml` and listed in both `README.md` and `fx-to-dotnet/README.md`.
- [ ] Every `speckit.fx-to-dotnet.*` reference resolves to a declared command.
- [ ] Each bash script has a PascalCase PowerShell twin; both are declared and `.ps1` is Windows PowerShell 5.1 compatible (ASCII/UTF-8-BOM; no `??`, `?:`, `ConvertFrom-Json -AsHashtable`).
- [ ] Required policies are loaded via `get_instructions` and cited in a `## Policies Applied` table.
- [ ] Added or updated tests covering this change (new script -> `tests/scripts/` + Pester for `.ps1`; new command/hook -> `tests/runtime/`; new invariant -> `tests/structural/`), or N/A with a reason: ___
- [ ] `CHANGELOG.md` `Unreleased` section updated if user-facing.
