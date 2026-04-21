# fx-to-dotnet-build-fix — Build Fix Loop

Run iterative `dotnet build` → diagnose errors → apply minimal fixes until build succeeds or user stops.

## Command

`speckit.fx-to-dotnet-build-fix.fix` — Specify the `.sln`, `.csproj`, `.vbproj`, or `.fsproj` to build.

## Prerequisites

None — this extension is self-contained and can be used standalone for any .NET project.

## Build Scripts

- `scripts/bash/dotnet-build.sh` — Bash build wrapper
- `scripts/powershell/dotnet-build.ps1` — PowerShell build wrapper

## State Files

- Reads/writes: `.fx-to-dotnet/{ProjectName}.md` (`## Build Fix` section)
