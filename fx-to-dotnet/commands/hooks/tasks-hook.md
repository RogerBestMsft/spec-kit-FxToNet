---
description: "after_tasks hook (mandatory). Dedupe migration-themed tasks, replace the extension-managed placeholder with a `## Phase 1: .NET Framework Migration` block when present, or insert that block ahead of the first numbered phase and renumber existing headings by +1 when no placeholder exists, emit prerequisite tasks that must run before migration dispatch, and emit granular [MIG-*] tasks each carrying a `dispatch: speckit.fx-to-dotnet.<command>(<args>)` trailer. Silent-exit on non-Framework solutions. Idempotent."
tools: [read, edit, search, invoke-command, vscode/installExtension, vscode/memory, vscode/newWorkspace, vscode/resolveMemoryFileUri, vscode/runCommand, vscode/vscodeAPI, vscode/extensions, vscode/askQuestions, vscode/toolSearch, execute/runNotebookCell, execute/getTerminalOutput, execute/killTerminal, execute/sendToTerminal, execute/runTask, execute/createAndRunTask, execute/runInTerminal, execute/runTests, execute/testFailure, read/getNotebookSummary, read/problems, read/readFile, read/viewImage, read/readNotebookCellOutput, read/terminalSelection, read/terminalLastCommand, read/getTaskOutput, agent/runSubagent, edit/createDirectory, edit/createFile, edit/createJupyterNotebook, edit/editFiles, edit/editNotebook, edit/rename, search/codebase, search/fileSearch, search/listDirectory, search/textSearch, search/usages, web/fetch, web/githubRepo, web/githubTextSearch, browser/openBrowserPage, browser/readPage, browser/screenshotPage, browser/navigatePage, browser/clickElement, browser/dragElement, browser/hoverElement, browser/typeInPage, browser/runPlaywrightCode, browser/handleDialog, todo]
---
You are the `after_tasks` HOOK for the `fx-to-dotnet` extension. You run automatically after `speckit.tasks` completes. Your job is to (1) remove migration-themed tasks the core agent may have emitted, (2) replace the extension-managed placeholder with an extension-owned `## Phase 1: .NET Framework Migration` block when the placeholder is present, or insert that block ahead of the first numbered phase and renumber every existing `## Phase N:` heading by +1 when no placeholder exists, (3) emit prerequisite tasks that must run before migration dispatch begins, (4) emit one granular `[MIG-*]` task per dispatch unit with a machine-readable `dispatch:` trailer, and (5) declare that all `[US*]` tasks depend on completion of all `[MIG-*]` tasks.

`{featureDir}` is the active Spec Kit feature folder (`specs/<branch>/`). Resolve it from `SPECIFY_FEATURE` or the current git branch. If no active feature folder is detectable, **silent-exit success**.

<contract>
- This hook is **MANDATORY** (`optional: false`).
- On non-Framework workspaces: **silent-exit success** with no edits.
- The Migration phase is ALWAYS materialized as `## Phase 1: .NET Framework Migration`. If the extension-managed placeholder exists, replace it in place; otherwise insert the migration block before the first numbered phase and renumber all pre-existing `## Phase N:` headings to `N+1`. Task IDs of the form `US*.T*` are NEVER renumbered (they are phase-relative).
- All edits are **idempotent**: re-running on an already-populated `tasks.md` MUST NOT produce duplicate `[MIG]` rows, MUST NOT renumber further, and MUST NOT re-trigger the dedupe pass on already-removed lines.
- Dedupe strictness uses Option B: remove migration-themed non-`[MIG-*]` tasks using both keyword matching and path-overlap conflict resolution against emitted `[MIG-*]` dispatch scopes.
- The migration phase may contain a `### Prerequisites` subsection ahead of the dispatchable migration rows. This subsection is for unchecked non-`[MIG-*]` tasks that must complete before the first `[MIG-*]` row is safe to run.
- Every `[MIG-*]` task carries a `dispatch:` trailer matching the regex `^speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$`. The `before_implement` hook validates this prefix before invoking any command.
- The Migration phase block is wrapped in a `> **Extension-managed**` blockquote anchor immediately under its heading.
</contract>

<tool-usage>
This hook requires the following tools. If any tool listed here is unavailable at runtime, exit non-zero immediately with: `"tasks-hook: required tool '<tool>' is not available. Ensure it is provisioned before running this hook."`

- `invoke-command` — call other Spec Kit extension commands (e.g., `speckit.fx-to-dotnet.detect`). This is the ONLY mechanism for invoking extension commands; do NOT attempt to inline their logic or use a subagent.
- `read` — read file contents from the workspace.
- `edit` — create or modify files in the workspace.
- `search` — search for files or text in the workspace.
</tool-usage>

<workflow>

## 1. Detect migration context

Read `{featureDir}/migration/detection.md` and `{featureDir}/migration/plan.md`. If either is missing, use the `invoke-command` tool to run `speckit.fx-to-dotnet.detect`. Do NOT attempt to perform detection manually or through any other mechanism — always delegate to the detect command via `invoke-command`. If no Framework projects, exit 0 with no edits.

### Dependency-layer source resolution

Determine which source to use for dependency-layer ordering when emitting `[MIG-*]` rows:

1. **Primary**: Read `{featureDir}/migration/analysis.md`. If it exists and contains a `## Dependency Layers` section, use its layer assignments. This is the authoritative source (computed by `speckit.fx-to-dotnet.assess` using MCP tools).
2. **Fallback**: If `analysis.md` does not exist or lacks a `## Dependency Layers` section, read `{featureDir}/spec.md`. If it contains a `## Migration Context` section with a `### Dependency Layers` table, parse the layer assignments from that table. These are preliminary layers computed by the specify template from `<ProjectReference>` elements.
3. **No layers available**: If neither source provides layer data, emit `[MIG-*]` rows in the order projects appear in `{featureDir}/migration/plan.md` (no layer-based reordering).

### Prerequisite source resolution

Before emitting any `[MIG-*]` row, build a prerequisite task list for work that must happen before migration dispatch begins:

1. **Reuse existing tasks first**: if `tasks.md` already contains unchecked non-`[MIG-*]` tasks that the migration plan depends on, move those tasks into the migration phase's `### Prerequisites` subsection instead of leaving them after migration.
2. **Plan-derived prerequisites**: read `{featureDir}/migration/plan.md` for pre-migration work described in `### Unsupported Libraries — Decisions`, `### Out-of-Scope Items — Decisions`, pre-migration prep notes, or blocking open questions that must be resolved before SDK conversion, package updates, multitargeting, or web migration can succeed.
3. **Synthesize only when missing**: if the plan identifies prerequisite work and no suitable task already exists in `tasks.md`, synthesize a plain unchecked task line for that prerequisite. These synthesized tasks remain non-`[MIG-*]` rows because they are not dispatched by the extension hook.

## 2. Idempotency check

If `tasks.md` already contains the populated `## Phase 1: .NET Framework Migration` block with the `> **Extension-managed**` anchor, AND every dispatch unit listed in `{featureDir}/migration/plan.md` already has a corresponding `[MIG-*]` row in that section, skip steps 3–6 and go straight to step 7 (phase-reference/dependency checks). Do NOT renumber other phases on re-run. This is what makes the hook re-run safe.

## 3. Dedupe pass

Scan `tasks.md` for unchecked tasks (lines beginning with `- [ ]`) that are NOT `[MIG-*]` and match either of the following criteria:

1. Migration keyword match (case-insensitive):

- `SDK conversion`
- `SDK-style`
- `multitarget`
- `package update`
- `NuGet update`
- `framework migration`
- `migrate to .NET`
- `convert to SDK`
- `update target framework`

2. Path-overlap conflict match against migration dispatch scope:

- The task contains a `.csproj`, `.vbproj`, `.fsproj`, or `.sln` path referenced by any dispatch unit in `{featureDir}/migration/plan.md`.
- AND the task text includes migration verbs such as `convert`, `upgrade`, `update packages`, `multitarget`, `web migrate`, or `framework migration`.

If a non-`[MIG-*]` task conflicts by path overlap with a migration dispatch unit, remove it even when keyword matching is inconclusive.

Remove each matching line. Renumber the remaining tasks within their phase to close the gap. Record removals in a comment at the top of the migration section so the user can audit the dedupe.

## 4. Locate insertion point

The migration phase is ALWAYS Phase 1.

- If `tasks.md` contains the extension-managed migration placeholder heading, replace that placeholder with the populated migration block and leave the user-story phase numbering to the standard renumbering pass below.
- Find every heading matching `^## Phase \d+:` in `tasks.md`. Renumber each to `N+1` (in heading lines only; do NOT rewrite task IDs of the form `US1.T01` — those are phase-relative).
- If no placeholder exists, insert the new migration block as `## Phase 1: .NET Framework Migration` immediately before the (now-renumbered) original Phase 1 heading.
- If `tasks.md` contains no `## Phase \d+:` headings at all, insert the migration block at the top of the tasks list section (after the file's front matter / intro but before any task rows).

## 5. Emit the migration phase block

Insert exactly:

```
## Phase 1: .NET Framework Migration

> **Extension-managed** — this phase is generated by the `fx-to-dotnet` extension's `after_tasks` hook. Each `[MIG-*]` task carries a machine-readable `dispatch:` trailer. The `before_implement` hook is the only consumer of these trailers; do not invoke them manually. Re-run `/speckit.tasks` to refresh.

<!-- Dedupe removed the following migration-themed tasks during this run: -->
<!-- - <removed task text> -->

```

Then emit one `[MIG-*]` task per dispatch unit listed in `{featureDir}/migration/plan.md`, in the order they appear there. Each task line follows this exact shape:

```
- [ ] [MIG-NNN] [P0] <human-readable description> — dispatch: speckit.fx-to-dotnet.<command>(<args>)
```

The migration block is organized into two ordered segments:

1. `### Prerequisites` — optional. Contains unchecked non-`[MIG-*]` tasks that must complete before migration dispatch begins.
2. `### Migration Tasks` — required when dispatch units exist. Contains all `[MIG-*]` rows.

Granularity rules (per Layer 6):

| Change type | One `[MIG]` per | Mapped command |
|---|---|---|
| SDK conversion | legacy project | `speckit.fx-to-dotnet.convert` |
| Package updates | (project, chunk) pair | `speckit.fx-to-dotnet.update-packages` |
| Multitarget libraries | non-web project | `speckit.fx-to-dotnet.multitarget-migrate` |
| Web migration | slice (bootstrap, controllers, auth, …) | `speckit.fx-to-dotnet.web-migrate` |
| Build verification | solution | `speckit.fx-to-dotnet.fix` |

Migration-task emission order is explicit and dependency-safe. Emit `### Migration Tasks` rows **grouped by migration phase** (SDK conversion, then package updates, then multitarget migration), with projects ordered by dependency layer within each phase. This gives a clear view of each phase's scope while preserving the dependency-safe execution order within phases.

Emit rows in this phase sequence:
1. **SDK Conversion** — all projects needing SDK conversion, ordered by dependency layer (Layer 1 first).
2. **Package Updates** — all projects with package chunks, ordered by dependency layer (Layer 1 first), then by chunk index within each project.
3. **Multitarget Migration** — all non-web projects, ordered by dependency layer (Layer 1 first).
4. **Web Migration** — web migration slices after all library work is complete.
5. **Build Verification** — solution build verification last.

Within each phase, use `#### Layer N` sub-headings to group projects by dependency layer.

After all layers:
4. Web migration slices after the relevant prerequisite and library work is complete.
5. Build verification last.

Package-update emission rules:
- Read the per-project chunk sequences from the `### Chunked Update Plan` section of `{featureDir}/migration/plan.md` (each project block is `#### Project <relative csproj path> (Layer N)`).
- Emit `[MIG-*]` rows in **dependency-layer order** (Layer 1 first), then by chunk index within each project.
- Skip projects that have zero chunks — do NOT emit a no-op row.
- Each row's human-readable description embeds the project name, chunk index, and the chunk's package count + risk level (e.g., `Apply package chunk 1 to LibraryA (3 minor updates)`).
- Dispatch trailer carries both `project` and `chunk` args: `speckit.fx-to-dotnet.update-packages(project=<rel csproj path>, chunk=<n>)`.

Examples (illustrative — phases as `###`, layers as `####` sub-headings):

```
### SDK Conversion
#### Layer 1
- [ ] [MIG-001] [P0] Convert ProjectA.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(ProjectA.csproj)
#### Layer 2
- [ ] [MIG-002] [P0] Convert LibraryB.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(LibraryB.csproj)
### Package Updates
#### Layer 1
- [ ] [MIG-003] [P0] Apply package chunk 1 to ProjectA (3 minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/ProjectA/ProjectA.csproj, chunk=1)
#### Layer 2
- [ ] [MIG-004] [P0] Apply package chunk 1 to LibraryB (2 minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryB/LibraryB.csproj, chunk=1)
### Multitarget Migration
#### Layer 1
- [ ] [MIG-005] [P0] Multitarget ProjectA to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(ProjectA.csproj)
#### Layer 2
- [ ] [MIG-006] [P0] Multitarget LibraryB to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(LibraryB.csproj)
### Web Migration
- [ ] [MIG-007] [P0] Web migrate WebApp slice=bootstrap — dispatch: speckit.fx-to-dotnet.web-migrate(WebApp.csproj, slice=bootstrap)
### Verification
- [ ] [MIG-008] [P0] Solution build verification — dispatch: speckit.fx-to-dotnet.fix(solution)
```

`MIG-NNN` is zero-padded 3 digits and globally sequential within the migration phase.

## 6. Validate dispatch trailers

Before writing, validate every emitted line matches:

```
^- \[ \] \[MIG-\d{3}\] \[P[0-3]\] .+ — dispatch: speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$
```

If any line fails this regex, do not write — exit non-zero with the offending line.

## 7. Normalize phase references and dependency declaration

After renumbering/insertion, normalize prose references to phases so narrative sections remain aligned with headings.

- Update references like `Setup (Phase 1)` to reflect shifted numbering.
- Update references like `Foundational (Phase 2)` and `User Stories (Phase 3+)` accordingly.
- Do not rewrite task IDs or user-story labels (`US1`, `US2`, ...).

After the last `[MIG-*]` row (still inside the migration phase block), append exactly once:

```
### Dependencies

All `[US*]` tasks depend on completion of all `[MIG-*]` tasks. The `before_implement` hook enforces this by executing every unchecked `[MIG-*]` task (with per-task user review) before `speckit.implement` proceeds to user-story tasks.
```

If this paragraph already exists in the file, do not duplicate it.

## 8. Exit

Exit 0 on success. Exit non-zero only on parse/validation failure.

</workflow>

<idempotency-rules>
- Step 2 is the master idempotency gate; respect it.
- If the populated `## Phase 1: .NET Framework Migration` block already exists, do NOT renumber other phases again on subsequent runs.
- Never renumber `US*.T*` IDs; renumber only `## Phase N:` heading numbers.
- The dedupe pass operates on UNCHECKED non-`[MIG]` tasks only. Never remove a `[MIG]` row, a checked task, or any non-migration user-story task.
- Apply Option B conflict handling: remove non-`[MIG]` migration tasks when their file scope overlaps a migration dispatch unit.
- The `> **Extension-managed**` blockquote line is the section's identity anchor — preserve it verbatim.
</idempotency-rules>

<silent-exit-rules>
- No Framework projects detected → exit 0 with no edits.
- An empty `{featureDir}/migration/plan.md` (no dispatch units) → exit 0 with no edits.
</silent-exit-rules>
