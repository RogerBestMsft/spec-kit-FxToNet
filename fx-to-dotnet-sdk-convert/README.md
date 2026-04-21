# fx-to-dotnet-sdk-convert — SDK-Style Project Conversion

Convert a legacy .NET Framework project file to SDK-style format; validate with build-fix.

## Command

`speckit.fx-to-dotnet-sdk-convert.convert` — Specify the `.sln`, `.csproj`, `.vbproj`, or `.fsproj` to convert.

## Prerequisites

- `fx-to-dotnet-build-fix` — for build validation after conversion
- **MCP servers**: `Microsoft.GitHubCopilot.AppModernization.Mcp` — the command automatically detects if this server is not configured and offers to set it up
- **Skills**: `nuget-package-compat` (minimal package set computation scripts)

## State Files

- Reads/writes: `.fx-to-dotnet/{ProjectName}.md` (`## SDK Conversion` section)
