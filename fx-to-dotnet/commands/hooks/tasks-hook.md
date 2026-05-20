---
description: "after_tasks hook (mandatory). Dedupe migration-themed tasks, insert a `## Phase 1: .NET Framework Migration` block ahead of all existing phases (renumbering them by +1), and emit granular [MIG-*] tasks each carrying a `dispatch: speckit.fx-to-dotnet.<command>(<args>)` trailer. Silent-exit on non-Framework solutions. Idempotent."
tools: [read, edit, search]
---
You are the `after_tasks` HOOK for the `fx-to-dotnet` extension. You run automatically after `speckit.tasks` completes. Your job is to (1) remove migration-themed tasks the core agent may have emitted, (2) insert an extension-owned `## Phase 1: .NET Framework Migration` block as the FIRST phase (renumbering every existing `## Phase N:` heading by +1), (3) emit one granular `[MIG-*]` task per dispatch unit with a machine-readable `dispatch:` trailer, and (4) declare that all `[US*]` tasks depend on completion of all `[MIG-*]` tasks.

`{featureDir}` is the active Spec Kit feature folder (`specs/<branch>/`). Resolve it from `SPECIFY_FEATURE` or the current git branch. If no active feature folder is detectable, **silent-exit success**.

<contract>
- This hook is **MANDATORY** (`optional: false`).
- On non-Framework workspaces: **silent-exit success** with no edits.
- The Migration phase is ALWAYS inserted as `## Phase 1: .NET Framework Migration` at the top of the phase list. All pre-existing `## Phase N:` headings are renumbered to `N+1`. Task IDs of the form `US*.T*` are NEVER renumbered (they are phase-relative).
- All edits are **idempotent**: re-running on an already-populated `tasks.md` MUST NOT produce duplicate `[MIG]` rows, MUST NOT renumber further, and MUST NOT re-trigger the dedupe pass on already-removed lines.
- Every `[MIG-*]` task carries a `dispatch:` trailer matching the regex `^speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$`. The `before_implement` hook validates this prefix before invoking any command.
- The Migration phase block is wrapped in a `> **Extension-managed**` blockquote anchor immediately under its heading.
- Inside the Migration phase block, `[MIG-*]` tasks are grouped by **kind** into four top-level sub-blocks emitted in this fixed order: `### Solution-Wide (Baseline)`, `### SDK-Style Conversion`, `### Package Updates`, `### Per-Project Migration`. Inside `### SDK-Style Conversion` and `### Package Updates`, rows are further grouped under `#### Layer N` subheadings (ascending, no gaps) sourced from the dependency-layer numbers in `{featureDir}/migration/plan.md`. Inside `### Per-Project Migration`, rows are grouped under `#### Project <relative csproj path>` subheadings in dependency-layer order. MIG numbering remains globally sequential across all sub-blocks. Empty sub-blocks are omitted entirely.
</contract>

<workflow>

## 1. Detect migration context

Read `{featureDir}/migration/detection.md` and `{featureDir}/migration/plan.md`. If either is missing, invoke `speckit.fx-to-dotnet.detect`. If no Framework projects, exit 0 with no edits.

## 2. Idempotency check

If `tasks.md` already contains the heading `## Phase 1: .NET Framework Migration` followed by a `> **Extension-managed**` blockquote, AND every dispatch unit listed in `{featureDir}/migration/plan.md` already has a corresponding `[MIG-*]` row in that section, skip steps 3–6 and go straight to step 7 (dependency declaration check). Do NOT renumber other phases on re-run. This is what makes the hook re-run safe.

**Sub-block upgrade for legacy blocks:** if the migration block is already present AND every dispatch unit has a corresponding `[MIG-*]` row BUT the block does not yet contain the four top-level sub-blocks (`### Solution-Wide (Baseline)`, `### SDK-Style Conversion`, `### Package Updates`, `### Per-Project Migration`) — e.g. it still uses the older interleaved `### Layer N` layout, or has no sub-blocks at all — perform a one-time in-place reshuffle: regroup the existing MIG rows under the four top-level sub-blocks (with nested `#### Layer N` inside SDK/Packages and `#### Project <rel csproj path>` inside Per-Project) according to each task's dispatch command and the per-task layer mapping derived from `{featureDir}/migration/plan.md`. Do NOT change MIG IDs, do NOT renumber other phases, and do NOT re-run the dedupe pass. After the upgrade, jump to step 7. The presence of the four sub-block headings (and their nested `#### Layer N` / `#### Project <path>` headings) counts as part of the extension-managed block for future idempotency checks.

## 3. Dedupe pass

Scan `tasks.md` for unchecked tasks (lines beginning with `- [ ]`) that are NOT `[MIG-*]` and whose text contains any of the migration keywords (case-insensitive):

- `SDK conversion`
- `SDK-style`
- `multitarget`
- `package update`
- `NuGet update`
- `framework migration`
- `migrate to .NET`
- `convert to SDK`
- `update target framework`

Remove each matching line. Renumber the remaining tasks within their phase to close the gap. Record removals in a comment at the top of the migration section so the user can audit the dedupe.

## 4. Locate insertion point

The migration phase is ALWAYS Phase 1.

- Find every heading matching `^## Phase \d+:` in `tasks.md`. Renumber each to `N+1` (in heading lines only; do NOT rewrite task IDs of the form `US1.T01` — those are phase-relative).
- Insert the new migration block as `## Phase 1: .NET Framework Migration` immediately before the (now-renumbered) original Phase 1 heading.
- If `tasks.md` contains no `## Phase \d+:` headings at all, insert the migration block at the top of the tasks list section (after the file's front matter / intro but before any task rows).

## 5. Emit the migration phase block

Insert exactly:

```
## Phase 1: .NET Framework Migration

> **Extension-managed** — this phase is generated by the `fx-to-dotnet` extension's `after_tasks` hook. Each `[MIG-*]` task carries a machine-readable `dispatch:` trailer. The `before_implement` hook is the only consumer of these trailers; do not invoke them manually. Re-run `/speckit.tasks` to refresh.

<!-- Dedupe removed the following migration-themed tasks during this run: -->
<!-- - <removed task text> -->

```

Then emit one `[MIG-*]` task per dispatch unit listed in `{featureDir}/migration/plan.md`, partitioned into four top-level sub-blocks emitted in this exact order:

1. `### Solution-Wide (Baseline)`
2. `### SDK-Style Conversion`
3. `### Package Updates`
4. `### Per-Project Migration`

Each task line follows this exact shape:

```
- [ ] [MIG-NNN] [P0] <human-readable description> — dispatch: speckit.fx-to-dotnet.<command>(<args>)
```

Granularity rules (per Layer 6):

| Change type | One `[MIG]` per | Mapped command | Lives under |
|---|---|---|---|
| Build verification | solution | `speckit.fx-to-dotnet.fix` | `### Solution-Wide (Baseline)` |
| SDK conversion | legacy project | `speckit.fx-to-dotnet.convert` | `### SDK-Style Conversion` → `#### Layer N` |
| Package updates | (project, chunk) pair | `speckit.fx-to-dotnet.update-packages` | `### Package Updates` → `#### Layer N` |
| Multitarget libraries | non-web project | `speckit.fx-to-dotnet.multitarget-migrate` | `### Per-Project Migration` → `#### Project <path>` |
| Web migration | slice (bootstrap, controllers, auth, …) | `speckit.fx-to-dotnet.web-migrate` | `### Per-Project Migration` → `#### Project <path>` |

Sub-block emission rules:
- The layer for each project comes from `{featureDir}/migration/plan.md` — specifically the `(Layer N)` annotation on each `#### Project <rel csproj path> (Layer N)` block and the `### Layer N` lists under `## Phase 1: SDK-Style Conversion` and `## Phase 3: Multitarget Migration`.
- `### Solution-Wide (Baseline)` is emitted first and currently contains only solution-scope tasks (e.g. `speckit.fx-to-dotnet.fix(solution)`). Placing it first establishes a build baseline before any conversion work begins.
- `### SDK-Style Conversion` groups all `convert` rows under `#### Layer 1`, `#### Layer 2`, …, in strictly ascending order with no gaps. Within a layer, list projects in the order they appear under that layer in `plan.md`.
- `### Package Updates` groups all `update-packages` rows under `#### Layer 1`, `#### Layer 2`, …, in strictly ascending order with no gaps. Within a layer, group rows for each project together in plan.md project order, and within each project emit chunks in ascending chunk index (chunk 1 before chunk 2).
- `### Per-Project Migration` groups all remaining per-project rows (`multitarget-migrate`, `web-migrate`) under `#### Project <relative csproj path>` headings. Project headings appear in dependency-layer order (Layer 1 projects first, then Layer 2, …; within a layer use plan.md order). Within a project, emit `multitarget-migrate` first, then `web-migrate` rows in the slice order they appear in `plan.md`. Web migration slices live under their owning web project's heading.
- Any sub-block that would contain zero rows is omitted entirely (no empty heading). The same applies to nested `#### Layer N` and `#### Project <path>` headings.
- `MIG-NNN` is zero-padded 3 digits and **globally sequential across all sub-blocks** (Solution-Wide → SDK-Style Conversion → Package Updates → Per-Project Migration) — numbering does NOT restart per sub-block, per layer, or per project.

Package-update emission rules:
- Read the per-project chunk sequences from the `### Chunked Update Plan` section of `{featureDir}/migration/plan.md` (each project block is `#### Project <relative csproj path> (Layer N)`).
- Emit `[MIG-*]` rows in **dependency-layer order** (Layer 1 first), then by chunk index within each project.
- Skip projects that have zero chunks — do NOT emit a no-op row.
- Each row's human-readable description embeds the project name, chunk index, and the chunk's package count + risk level (e.g., `Apply package chunk 1 to LibraryA (3 minor updates)`).
- Dispatch trailer carries both `project` and `chunk` args: `speckit.fx-to-dotnet.update-packages(project=<rel csproj path>, chunk=<n>)`.

Worked end-to-end example (illustrative — three layers, one web app, one solution-wide task):

```
### Solution-Wide (Baseline)

- [ ] [MIG-001] [P0] Solution build verification — dispatch: speckit.fx-to-dotnet.fix(solution)

### SDK-Style Conversion

#### Layer 1

- [ ] [MIG-002] [P0] Convert LibraryA.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(src/LibraryA/LibraryA.csproj)
- [ ] [MIG-003] [P0] Convert LibraryB.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(src/LibraryB/LibraryB.csproj)

#### Layer 2

- [ ] [MIG-004] [P0] Convert ServicesLib.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(src/Services/ServicesLib.csproj)

#### Layer 3

- [ ] [MIG-005] [P0] Convert WebApp.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(src/WebApp/WebApp.csproj)

### Package Updates

#### Layer 1

- [ ] [MIG-006] [P0] Apply package chunk 1 to LibraryA (3 minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryA/LibraryA.csproj, chunk=1)
- [ ] [MIG-007] [P0] Apply package chunk 2 to LibraryA (1 major update) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryA/LibraryA.csproj, chunk=2)
- [ ] [MIG-008] [P0] Apply package chunk 1 to LibraryB (2 minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryB/LibraryB.csproj, chunk=1)

#### Layer 2

- [ ] [MIG-009] [P0] Apply package chunk 1 to ServicesLib (1 major update) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/Services/ServicesLib.csproj, chunk=1)

#### Layer 3

- [ ] [MIG-010] [P0] Apply package chunk 1 to WebApp (2 major updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/WebApp/WebApp.csproj, chunk=1)

### Per-Project Migration

#### Project src/LibraryA/LibraryA.csproj

- [ ] [MIG-011] [P0] Multitarget LibraryA to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(src/LibraryA/LibraryA.csproj)

#### Project src/LibraryB/LibraryB.csproj

- [ ] [MIG-012] [P0] Multitarget LibraryB to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(src/LibraryB/LibraryB.csproj)

#### Project src/Services/ServicesLib.csproj

- [ ] [MIG-013] [P0] Multitarget ServicesLib to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(src/Services/ServicesLib.csproj)

#### Project src/WebApp/WebApp.csproj

- [ ] [MIG-014] [P0] Web migrate WebApp slice=bootstrap — dispatch: speckit.fx-to-dotnet.web-migrate(src/WebApp/WebApp.csproj, slice=bootstrap)
- [ ] [MIG-015] [P0] Web migrate WebApp slice=controllers — dispatch: speckit.fx-to-dotnet.web-migrate(src/WebApp/WebApp.csproj, slice=controllers)
- [ ] [MIG-016] [P0] Web migrate WebApp slice=auth — dispatch: speckit.fx-to-dotnet.web-migrate(src/WebApp/WebApp.csproj, slice=auth)
```

## 6. Validate dispatch trailers and layer grouping

Before writing, validate every emitted `[MIG-*]` line matches:

```
^- \[ \] \[MIG-\d{3}\] \[P[0-3]\] .+ — dispatch: speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$
```

Additionally, validate the structural layout of the migration phase block:

- Every `[MIG-*]` row sits under exactly one of: `### Solution-Wide (Baseline)`, a `#### Layer N` heading nested under `### SDK-Style Conversion` or `### Package Updates`, or a `#### Project <relative csproj path>` heading nested under `### Per-Project Migration`. No MIG rows sit directly under `## Phase 1: .NET Framework Migration` or directly under a top-level `###` sub-block heading.
- The top-level sub-block headings, when present, appear in this exact order: `### Solution-Wide (Baseline)`, `### SDK-Style Conversion`, `### Package Updates`, `### Per-Project Migration`, followed by `### Dependencies`. Any sub-block with zero rows is omitted entirely (no empty heading).
- Inside `### SDK-Style Conversion` and inside `### Package Updates`, `#### Layer N` subheadings appear in strictly ascending order starting at `#### Layer 1`, with no gaps.
- Inside `### Per-Project Migration`, `#### Project <relative csproj path>` subheadings appear in dependency-layer order (Layer 1 projects first, then Layer 2, …).
- MIG IDs are zero-padded 3-digit and strictly increasing in document order across all sub-blocks.

If any line or structural rule fails, do not write — exit non-zero with the offending line or heading.

## 7. Dependency declaration

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
- If `## Phase 1: .NET Framework Migration` already exists, do NOT renumber other phases again on subsequent runs.
- Never renumber `US*.T*` IDs; renumber only `## Phase N:` heading numbers.
- The dedupe pass operates on UNCHECKED non-`[MIG]` tasks only. Never remove a `[MIG]` row, a checked task, or anything from the user-story phases.
- The `> **Extension-managed**` blockquote line is the section's identity anchor — preserve it verbatim.
- The four top-level sub-block headings (`### Solution-Wide (Baseline)`, `### SDK-Style Conversion`, `### Package Updates`, `### Per-Project Migration`) and their nested `#### Layer N` / `#### Project <relative csproj path>` headings inside the migration block are part of the extension-managed block and MUST be preserved on re-run. A legacy migration block lacking these sub-blocks (or still using the older interleaved `### Layer N` layout) is upgraded in place exactly once (see step 2's *Sub-block upgrade for legacy blocks*) without renumbering MIG IDs or re-running the dedupe pass.
</idempotency-rules>

<silent-exit-rules>
- No Framework projects detected → exit 0 with no edits.
- An empty `{featureDir}/migration/plan.md` (no dispatch units) → exit 0 with no edits.
</silent-exit-rules>
