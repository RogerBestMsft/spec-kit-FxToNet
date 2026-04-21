# fx-to-dotnet-package-compat — Package Compatibility Migration

Execute a pre-built chunked package update plan; invoke build-fix after each chunk.

## Command

`speckit.fx-to-dotnet-package-compat.update` — Requires solution path, target framework, and the chunked update plan from the Migration Planner.

## Prerequisites

- `fx-to-dotnet-build-fix` — for build validation after each chunk

## State Files

- Reads/writes: `.fx-to-dotnet/package-updates.md`
- Reads/writes: `.fx-to-dotnet/preferences.md` (`[package-compat]` section)
