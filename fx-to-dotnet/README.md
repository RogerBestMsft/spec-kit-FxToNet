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

## SDD Workflow Integration

Starting in v0.2.0, the extension hooks into Spec Kit's core Spec-Driven Development workflow (`speckit.specify` → `speckit.plan` → `speckit.tasks` → `speckit.implement`). Both the standalone orchestrator and the SDD integration paths remain fully functional.

### Two Usage Paths

| Path | Entry Point | Best For |
|------|-------------|----------|
| **Standalone** | `speckit.fx-to-dotnet.orchestrate <solutionPath>` | Dedicated migration sessions with full orchestrator control |
| **SDD Integrated** | `speckit.specify "Migrate MyApp from .NET Framework to .NET 10"` | Migration as part of a broader feature spec, or when using the standard SDD workflow |

### How SDD Hooks Work

When the extension is installed, it registers four lifecycle hooks that activate during the core SDD commands. All hooks are **optional** — you're prompted before each one runs, and non-migration projects are unaffected (hooks detect migration context and bail out silently).

| SDD Command | Hook Event | Bridge Command | What It Does |
|-------------|------------|----------------|--------------|
| `speckit.specify` | `after_specify` | `speckit.fx-to-dotnet.specify-hook` | Detects .NET Framework migration context in the spec, runs `assess`, appends `## Migration Assessment Summary` to `spec.md` |
| `speckit.plan` | `after_plan` | `speckit.fx-to-dotnet.plan-hook` | Generates a structured migration plan via `plan`, appends `## .NET Migration Plan` to the SDD `plan.md` |
| `speckit.tasks` | `after_tasks` | `speckit.fx-to-dotnet.tasks-hook` | Produces `[MIG]`-tagged layer-level tasks for SDK conversion, package updates, multitargeting, and web migration |
| `speckit.implement` | `before_implement` | `speckit.fx-to-dotnet.implement-hook` | Executes `[MIG]` tasks by dispatching to FxToNet commands (convert, update-packages, multitarget-migrate, web-migrate) with layer checkpoints |

### Artifact Mapping

The SDD integration writes summary data into standard SDD artifacts while keeping full migration state in `.fx-to-dotnet/`:

| SDD Artifact | Migration Section Added | Full Detail In |
|-------------|------------------------|----------------|
| `spec.md` | `## Migration Assessment Summary` | `.fx-to-dotnet/analysis.md`, `.fx-to-dotnet/package-updates.md` |
| `plan.md` | `## .NET Migration Plan` | `.fx-to-dotnet/plan.md` |
| `tasks.md` | `## .NET Framework Migration` (with `[MIG]` tasks) | — (tasks.md is the source of truth) |

### State Compatibility

The SDD bridge commands write the same `lastCompletedPhase` values to `.fx-to-dotnet/plan.md` as the standalone orchestrator. If you start with the SDD path and later switch to the orchestrator (or vice versa), the orchestrator recognizes completed phases and offers to resume.
