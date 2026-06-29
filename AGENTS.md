# AGENTS.md

Portable entry point for AI coding agents working in `spec-kit-FxToNet`.

**The canonical, detailed guide is [.github/copilot-instructions.md](.github/copilot-instructions.md).**
Read it first. Path-scoped rules live under [.github/instructions/](.github/instructions/).
This file is intentionally a thin pointer — do not duplicate content here.

## What this is

A single [Spec Kit](https://github.com/github/spec-kit) extension, `fx-to-dotnet`, that
migrates .NET Framework apps to modern .NET, plus a companion preset and tooling. The
deliverables are markdown commands/policies, YAML manifests, and paired shell/PowerShell
scripts — not application code. The source of truth for commands, hooks, and version is
[fx-to-dotnet/extension.yml](fx-to-dotnet/extension.yml) and
[fx-to-dotnet/preset.yml](fx-to-dotnet/preset.yml); never rely on memory for those.

## Critical rules (full details in copilot-instructions.md)

1. **One version** across `extension.yml`, `preset.yml`, and `README.md`; bump via
   `support_scripts/bump-version.*`, never by hand.
2. **Command frontmatter**: non-empty `description`; `tools` is a list; every
   `speckit.fx-to-dotnet.*` reference resolves to a declared command.
3. **Cross-references resolve** — `python support_scripts/cross-reference-audit.py`.
4. **Script parity**: each `bash/*.sh` has a PascalCase `powershell/*.ps1` twin, both
   declared in `extension.yml`.
5. **PowerShell 5.1 compatible** `.ps1` (ASCII/UTF-8-BOM; no `??`, `?:`,
   `ConvertFrom-Json -AsHashtable`).
6. **Policy proof**: required policies are loaded via `get_instructions(kind='policy', …)`
   and cited in a `## Policies Applied` table.
7. **Hooks**: all mandatory except `verify-hook`; `before_implement` is the gate that
   blocks `/speckit.implement`.

## Validate before finishing (mirrors CI)

```
python support_scripts/version-check.py
python support_scripts/cross-reference-audit.py
pytest tests/structural tests/scripts
```

See [.github/copilot-instructions.md](.github/copilot-instructions.md) for the full
checklist, common-change recipes, and architecture.
