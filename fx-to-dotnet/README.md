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

## Lifecycle Integration (v0.5.0+)

From v0.4.0 the extension integrates tightly with the standard Spec Kit lifecycle (`specify → plan → tasks → implement`) via five lifecycle hooks. Migration content is owned end-to-end by the extension; user-story implementation is gated behind completion of all migration tasks.

**Path convention (v0.7.0+).** All migration artifacts live under the active Spec Kit feature folder at `{featureDir}/migration/` (i.e. `specs/<branch>/migration/`), colocated with `spec.md`, `plan.md`, and `tasks.md`. This makes migration state per-feature (each branch gets isolated state) and lets core Spec Kit (`/speckit.analyze`, `/speckit.verify`) discover them by convention since it already operates on the active feature dir. Hooks resolve `{featureDir}` from the `SPECIFY_FEATURE` env var or the current git branch and silent-exit if no active feature folder is detectable. (History: v0.5.0 introduced `.specify/migration/analysis.md` as a shared artifact; v0.6.0 added `plan.md` and `orchestration.md` alongside it; v0.7.0 relocated all migration files to the active feature folder.)

| Event | Hook command | Optional? | Role |
|---|---|---|---|
| `after_specify` | `speckit.fx-to-dotnet.specify-hook` | **no** | Detect Framework projects; annotate `spec.md` with `## Migration Context Detected`. Silent-exit on non-Framework workspaces. |
| `after_plan` | `speckit.fx-to-dotnet.plan-hook` | **no** | Run `assess` + `plan`; produce `{featureDir}/migration/analysis.md` and `{featureDir}/migration/plan.md` (both shared); annotate `plan.md` with `## .NET Migration Plan`. |
| `after_tasks` | `speckit.fx-to-dotnet.tasks-hook` | **no** | Dedupe migration tasks the core agent emitted; insert `## Phase N: .NET Framework Migration` ahead of user stories; emit granular `[MIG-*]` rows with `dispatch:` trailers. |
| `before_implement` | `speckit.fx-to-dotnet.implement-hook` | **no** | **The gate.** Verify preconditions; per-task review of every `[MIG-*]`; validate dispatch namespace; only then allow `speckit.implement` to run user-story tasks. |
| `after_implement` | `speckit.fx-to-dotnet.verify-hook` | yes | Solution build verification; write `{featureDir}/migration/completion.md`; annotate plan + tasks with verification status. |

All mandatory hooks **silent-exit success** on non-Framework workspaces, so they never block ordinary (non-migration) Spec Kit usage.

### `[MIG-*]` Task Format

The `after_tasks` hook emits one row per granular dispatch unit. Each row carries a machine-readable trailer:

```
- [ ] [MIG-001] [P0] Convert ProjectA.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(ProjectA.csproj)
- [ ] [MIG-002] [P0] Apply package chunk 1 (minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(chunk=1)
- [ ] [MIG-003] [P0] Multitarget LibraryA to net10.0 — dispatch: speckit.fx-to-dotnet.library-update(LibraryA.csproj)
- [ ] [MIG-004] [P0] Web migrate WebApp slice=bootstrap — dispatch: speckit.fx-to-dotnet.web-app-migration(WebApp.csproj, slice=bootstrap)
```

The `dispatch:` trailer is parsed and validated by the `before_implement` hook against the regex `^speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$`. Targets that do not match the `speckit.fx-to-dotnet.` prefix are rejected and the task is marked `[~]` with a `dispatch-rejected` audit-log entry — this is the technical enforcement that **migrations only run extension-owned commands**.

### Precondition Gate

`speckit.implement` is blocked until ALL of the following exist:

1. `{featureDir}/migration/analysis.md` (from `assess` — shared artifact)
2. `{featureDir}/migration/plan.md` with phase sections (from `plan` — shared artifact)
3. `tasks.md` containing at least one `[MIG-*]` task

If any precondition is missing, the `before_implement` hook exits non-zero with a remediation message that points the user back to `/speckit.plan` → `/speckit.tasks` → `/speckit.implement`.

### Per-Task Review

The `before_implement` hook walks each unchecked `[MIG-*]` row in document order. For every row the user is shown a preview and one of four choices:

- `approve` — invoke the dispatch target now
- `skip` — mark `[~]` and continue
- `abort` — stop the run; leave remaining rows unchecked
- `autoApprove-rest` — invoke this and all subsequent rows without further outer prompts

**Build failures inside an invoked workflow always pause for review**, even when `autoApprove-rest` is active. State is persisted to `{featureDir}/migration/implement-state.md` and the run is resumable.

After all `[MIG-*]` rows are resolved the hook appends `## Migration Execution Summary` to `plan.md` and inserts a `> ✓ Migration Complete` checkpoint above the first `[US*]` task in `tasks.md`.

### Companion Preset (optional)

The sibling [presets/fx-to-dotnet-sdd/](../presets/fx-to-dotnet-sdd/) preset overrides core `speckit.tasks` and `speckit.implement` so the core agent never emits competing migration content (Layer 4 of the integration plan). Hooks alone work without the preset; the preset is the deterministic backstop.

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

All migration files live under the active Spec Kit feature folder at `{featureDir}/migration/` (i.e. `specs/<branch>/migration/`).

Shared (discoverable by Spec Kit core and other extensions):
- `analysis.md` — assessment report (assess output)
- `plan.md` — migration plan (plan output)
- `orchestration.md` — orchestrator phase-completion state

Private (extension state):
- `package-updates.md` — package compatibility analysis + execution state
- `preferences.md` — continuation preferences
- `detection.md` — framework-detection cache
- `implement-state.md` — per-task state for the `before_implement` gate
- `{ProjectName}.md` — per-project migration state

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
