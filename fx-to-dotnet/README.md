# fx-to-dotnet — Orchestrator

Orchestrates end-to-end .NET Framework to modern .NET migration across 7 phases.

## Command

`speckit.fx-to-dotnet.orchestrate` — Specify a `.sln`/`.slnx` path and optional target framework (default: `net10.0`).

## Phases

1. **Assessment** → `speckit.fx-to-dotnet-assess.assess`
2. **Planning** → `speckit.fx-to-dotnet-plan.plan`
3. **SDK Conversion** → `speckit.fx-to-dotnet-sdk-convert.convert` (layer-by-layer)
4. **Package Compatibility** → `speckit.fx-to-dotnet-package-compat.update`
5. **Multitarget Migration** → `speckit.fx-to-dotnet-multitarget.migrate` (layer-by-layer)
6. **Web Migration** → `speckit.fx-to-dotnet-web-migrate.migrate`
7. Completion / Deferred Work

## Prerequisites

All sibling extensions must be installed:

- `fx-to-dotnet-assess`
- `fx-to-dotnet-plan`
- `fx-to-dotnet-sdk-convert`
- `fx-to-dotnet-build-fix`
- `fx-to-dotnet-package-compat`
- `fx-to-dotnet-multitarget`
- `fx-to-dotnet-web-migrate`
- `fx-to-dotnet-detect-project`
- `fx-to-dotnet-route-inventory`
- `fx-to-dotnet-policies`

## State Files

- Reads/writes: `.fx-to-dotnet/plan.md`
- Reads: `.fx-to-dotnet/analysis.md`, `.fx-to-dotnet/package-updates.md`
