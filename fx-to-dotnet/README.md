# fx-to-dotnet — .NET Framework to Modern .NET Migration

A single Spec Kit extension that orchestrates migrating .NET Framework applications to modern .NET (e.g. .NET 10) through a 7-phase workflow.

## Commands

| Command | Description |
|---------|-------------|
| `speckit.fx-to-dotnet.orchestrate` | Orchestrator — drives the 7-phase migration flow |
| `speckit.fx-to-dotnet.assess` | Phase 1: Gather solution info, classify projects, audit package compatibility |
| `speckit.fx-to-dotnet.plan` | Phase 2: Synthesize assessment into an actionable migration plan |
| `speckit.fx-to-dotnet.convert` | Phase 3: Convert legacy project files to SDK-style format |
| `speckit.fx-to-dotnet.fix` | Cross-cutting: Iterative build → diagnose → fix loop |
| `speckit.fx-to-dotnet.update-packages` | Phase 4: Execute chunked package compatibility updates |
| `speckit.fx-to-dotnet.multitarget-migrate` | Phase 5: Add modern .NET target framework, fix API issues |
| `speckit.fx-to-dotnet.web-migrate` | Phase 6: ASP.NET Framework to ASP.NET Core web migration |
| `speckit.fx-to-dotnet.detect` | Utility: Determine project type, SDK-style status, classification |
| `speckit.fx-to-dotnet.inventory` | Utility: Extract route/endpoint inventory from legacy ASP.NET |
| `speckit.fx-to-dotnet.show-policy` | Display a named migration policy document |

## Quick Start

Specify a `.sln`/`.slnx` path and optional target framework (default: `net10.0`):

```
speckit.fx-to-dotnet.orchestrate <solutionPath> [targetFramework]
```

## Phases

1. **Assessment** → `speckit.fx-to-dotnet.assess`
2. **Planning** → `speckit.fx-to-dotnet.plan`
3. **SDK Conversion** → `speckit.fx-to-dotnet.convert` (layer-by-layer)
4. **Package Compatibility** → `speckit.fx-to-dotnet.update-packages`
5. **Multitarget Migration** → `speckit.fx-to-dotnet.multitarget-migrate` (layer-by-layer)
6. **Web Migration** → `speckit.fx-to-dotnet.web-migrate`
7. Completion / Deferred Work

## Prerequisites

- **Spec Kit** >= 0.1.0
- **.NET SDK** (for `dotnet build` via the fix command)
- **MCP Server**: `Microsoft.GitHubCopilot.Modernization.Mcp` (required by assess and convert commands)

## State Files

- Reads/writes: `.fx-to-dotnet/plan.md`
- Reads: `.fx-to-dotnet/analysis.md`, `.fx-to-dotnet/package-updates.md`

## Standalone Usage

Some commands can be used independently outside the full migration suite:

- **`speckit.fx-to-dotnet.fix`** — Useful for any .NET project; iteratively builds and fixes compilation errors
- **`speckit.fx-to-dotnet.detect`** — Classifies any .NET project (SDK-style, web host, service, library, etc.)
- **`speckit.fx-to-dotnet.inventory`** — Extracts endpoint inventory from any legacy ASP.NET web project

## Known Limitations

- **Single web-app-host per run** — Phase 6 (ASP.NET Core migration) handles one web host project at a time; solutions with multiple web applications require sequential runs or user selection
- **No project filtering** — All projects in the solution are included in assessment and planning; there is no mechanism to exclude deprecated or out-of-scope projects
- **No cross-project failure recovery** — If a project fails during conversion, there is no defined strategy for whether to block the solution, skip the failed project, or continue with dependent layers
- **No multi-solution / monorepo support** — The extension expects a single `.sln` file; repositories with multiple solutions require separate invocations
- **Package updates are solution-global** — Package compatibility updates are applied across the entire solution with no per-project override for conflicting requirements
- **No per-layer build validation** — Layer completion is treated as a checkpoint but does not mandate a verification build before advancing to the next layer
