# fx-to-dotnet-multitarget — Multitarget Migration

Add modern .NET target framework; identify and fix pre-migration API issues; validate with build-fix.

## Command

`speckit.fx-to-dotnet-multitarget.migrate` — Specify the `.sln`, `.csproj`, `.vbproj`, or `.fsproj` and target frameworks to add (default: `net10.0`).

## Prerequisites

- `fx-to-dotnet-build-fix` — for build validation
- `fx-to-dotnet-policies` — for System.Web adapters, EF6, and Windows Service policies

## State Files

- Reads/writes: `.fx-to-dotnet/{ProjectName}.md` (`## Multitarget` section)
- Reads/writes: `.fx-to-dotnet/preferences.md` (`[multitarget]` section)
