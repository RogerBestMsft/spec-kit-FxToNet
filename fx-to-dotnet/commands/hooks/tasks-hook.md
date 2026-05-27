---
description: "after_tasks hook (mandatory). Dedupe migration-themed tasks, insert a `## Phase N: .NET Framework Migration` block (with six named sub-layers) after the Setup/Foundational phases and immediately before the first user-story phase (renumbering only the phases that follow), and emit granular [MIG-*] tasks — active tasks (Layers 1–5) carry a `dispatch:` trailer; deferred/out-of-scope items (Layer 6) carry a `deferred:` trailer for manual acknowledgment. Silent-exit on non-Framework solutions. Idempotent."
tools: [read, edit, search]
---
You are the `after_tasks` HOOK for the `fx-to-dotnet` extension. You run automatically after `speckit.tasks` completes. Your job is to (1) remove migration-themed tasks the core agent may have emitted, (2) insert an extension-owned `## Phase N: .NET Framework Migration` block (organized into six named sub-layers) immediately AFTER the Setup/Foundational phases and BEFORE the first user-story phase (renumbering only the phases that follow the insertion point), (3) emit one granular `[MIG-*]` task per work unit — active tasks carry a `dispatch:` trailer; deferred/out-of-scope items carry a `deferred:` trailer for manual acknowledgment — and (4) declare that all `[US*]` tasks depend on completion of all `[MIG-*]` tasks.

`{featureDir}` is the active Spec Kit feature folder (`specs/<branch>/`). Resolve it from `SPECIFY_FEATURE` or the current git branch. If no active feature folder is detectable, **silent-exit success**.

<contract>
- This hook is **MANDATORY** (`optional: false`).
- On non-Framework workspaces: **silent-exit success** with no edits.
- Setup and Foundational phases ALWAYS come first. The Migration phase is inserted immediately AFTER the last non-user-story prerequisite phase (Setup, Foundational, and any other extension- or core-emitted prerequisite phase whose tasks are not `[US*]`) and immediately BEFORE the first user-story phase. Only the phases at or after the insertion point are renumbered (each by +1). Phases preceding it keep their existing numbers. Task IDs of the form `US*.T*` are NEVER renumbered (they are phase-relative).
- All edits are **idempotent**: re-running on an already-populated `tasks.md` MUST NOT produce duplicate `[MIG]` rows, MUST NOT renumber further, and MUST NOT re-trigger the dedupe pass on already-removed lines.
- Active migration `[MIG-*]` tasks (Layers 1–5) carry a `dispatch:` trailer matching `^speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$`. The `before_implement` hook validates this prefix before invoking any command.
- Deferred `[MIG-*]` tasks (Layer 6) carry a `deferred:` trailer containing the post-migration action text. The `before_implement` hook presents them for manual acknowledgment — no command is invoked.
- The Migration phase block is wrapped in a `> **Extension-managed**` blockquote anchor immediately under its heading.
</contract>

<workflow>

## 1. Detect migration context

Read `{featureDir}/migration/detection.md` and `{featureDir}/migration/plan.md`. If either is missing, invoke `speckit.fx-to-dotnet.detect`. If no Framework projects, exit 0 with no edits.

## 2. Idempotency check

If `tasks.md` already contains ALL of the following, skip steps 3–6 and go straight to step 7 (dependency declaration check):

1. A heading matching `## Phase \d+: \.NET Framework Migration` followed by a `> **Extension-managed**` blockquote.
2. All required `### Layer N:` sub-headings — Layers 1–5 are always required; Layer 6 is required only if `{featureDir}/migration/plan.md` contains a non-empty `### Out-of-Scope Items — Decisions` table.
3. Every dispatch unit and out-of-scope item listed in `{featureDir}/migration/plan.md` already has a corresponding `[MIG-*]` row in the appropriate sub-layer.

Do NOT renumber other phases on re-run. If the `## Phase \d+: .NET Framework Migration` heading exists but any sub-layer heading is missing (e.g., from a pre-layered run), re-emit the full block content in place — do NOT re-run the phase insertion or renumber phases again.

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

The migration phase MUST follow Setup/Foundational and precede the first user-story phase.

- Enumerate every heading matching `^## Phase (\d+): (.+)$` in `tasks.md`, preserving file order.
- Classify each phase as a **user-story phase** if its heading title matches `/user[\s-]?stor(y|ies)/i` OR its body (the lines between this heading and the next `## ` heading) contains at least one task ID of the form `[US\d`. Otherwise classify it as a **prerequisite phase** (Setup, Foundational, Polish/Cross-Cutting placed before user stories, etc.).
- The **insertion point** is the position immediately before the FIRST user-story phase heading.
- Renumber ONLY the phases at and after the insertion point: each becomes `N+1`. Phases preceding the insertion point keep their existing numbers. Never rewrite task IDs of the form `US1.T01` — those are phase-relative.
- The new migration heading's number is `(number of prerequisite phases before the insertion point) + 1`. For the common Spec Kit shape (`Phase 1: Setup`, `Phase 2: Foundational`, `Phase 3: User Story 1`, …) this yields `## Phase 3: .NET Framework Migration` and renumbers the user-story phases from 3,4,5,… to 4,5,6,….
- If `tasks.md` contains no user-story phases (no headings classified as user-story), append the migration block AFTER the last existing `## Phase N:` heading's body, numbered `(last existing phase number) + 1`. Do not renumber anything.
- If `tasks.md` contains no `## Phase \d+:` headings at all, insert the migration block as `## Phase 1: .NET Framework Migration` at the top of the tasks list section (after the file's front matter / intro but before any task rows). This is the only case where Migration may be Phase 1.
- The preset's placeholder heading (`## Phase N: .NET Framework Migration (extension-managed)`) emitted by the `tasks.md` template override, if present, is REPLACED in place: use its position as the insertion point (do not double-insert, do not shift it), then assign it the correct sequential number per the rules above.

## 5. Emit the migration phase block

Insert exactly (substituting `N` with the phase number computed in step 4):

```
## Phase N: .NET Framework Migration

> **Extension-managed** — this phase is generated by the `fx-to-dotnet` extension's `after_tasks` hook. Active tasks (Layers 1–5) carry a machine-readable `dispatch:` trailer; deferred items (Layer 6) carry a `deferred:` trailer for manual acknowledgment. The `before_implement` hook is the only consumer of these trailers; do not invoke them manually. Re-run `/speckit.tasks` to refresh.

<!-- Dedupe removed the following migration-themed tasks during this run: -->
<!-- - <removed task text> -->

```

Then emit `[MIG-*]` tasks organized under `### Layer N:` sub-headings as described below. `MIG-NNN` is zero-padded 3 digits and globally sequential across all layers (Layer 1 starts at `MIG-001`; each subsequent layer continues the sequence where the previous layer left off).

### Layer 1: SDK-Style Conversion

One `[MIG-*]` task per legacy project requiring SDK conversion, in dependency-layer order (Layer 1 projects first). Read the projects to convert from `## Phase 1: SDK-Style Conversion` in `{featureDir}/migration/plan.md`.

```
- [ ] [MIG-NNN] [P0] Convert <project name>.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(<rel csproj path>)
```

Projects already SDK-style (`skip-already-sdk`) and web-app-host projects (excluded from SDK conversion per Phase 1 of `plan.md`) are NOT emitted here.

### Layer 2: Package Updates

One `[MIG-*]` task per (project, chunk) pair, in dependency-layer order. Read from the `### Chunked Update Plan` section of `{featureDir}/migration/plan.md` (each project block is `#### Project <relative csproj path> (Layer N)`).

```
- [ ] [MIG-NNN] [P0] Apply package chunk <n> to <project name> (<count> <minor|major> updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=<rel csproj path>, chunk=<n>)
```

- Emit rows in dependency-layer order (Layer 1 first), then by chunk index within each project.
- Skip projects with zero chunks — do NOT emit a no-op row.

### Layer 3: Multitarget Libraries

One `[MIG-*]` task per non-web library project scheduled for multitargeting, in dependency-layer order. Read from `## Phase 3: Multitarget Migration` in `{featureDir}/migration/plan.md`.

```
- [ ] [MIG-NNN] [P0] Multitarget <project name> to <targetFramework> — dispatch: speckit.fx-to-dotnet.multitarget-migrate(<rel csproj path>)
```

### Layer 4: Web App Migration

One `[MIG-*]` task per (web-app-host project, migration slice), in the order slices appear in `## Phase 4: ASP.NET Core Web Migration` in `{featureDir}/migration/plan.md`.

```
- [ ] [MIG-NNN] [P0] Web migrate <project name> slice=<slice> — dispatch: speckit.fx-to-dotnet.web-migrate(<rel csproj path>, slice=<slice>)
```

If no web-app-host projects exist in `plan.md`, omit the `### Layer 4: Web App Migration` heading entirely.

### Layer 5: Build Verification

Exactly one task:

```
- [ ] [MIG-NNN] [P0] Solution build verification — dispatch: speckit.fx-to-dotnet.fix(solution)
```

### Layer 6: Deferred Work

Parse the `### Out-of-Scope Items — Decisions` table from `{featureDir}/migration/plan.md`. For each data row, emit one task using the `Item` column as the description and the `Post-Migration Action` column as the deferred value.

```
- [ ] [MIG-NNN] [P2] <Item> (deferred — post-migration) — deferred: <Post-Migration Action>
```

- Priority is `[P2]` (not `[P0]`) — deferred items are tracked but lower-priority than active migration work.
- If the `### Out-of-Scope Items — Decisions` table is absent or has no data rows, **omit the `### Layer 6: Deferred Work` heading entirely** — do not emit an empty sub-section.

Granularity rules:

| Change type | One `[MIG]` per | Trailer |
|---|---|---|
| SDK conversion | legacy project | `dispatch: speckit.fx-to-dotnet.convert(...)` |
| Package updates | (project, chunk) pair | `dispatch: speckit.fx-to-dotnet.update-packages(...)` |
| Multitarget libraries | non-web project | `dispatch: speckit.fx-to-dotnet.multitarget-migrate(...)` |
| Web migration | slice (bootstrap, controllers, auth, …) | `dispatch: speckit.fx-to-dotnet.web-migrate(...)` |
| Build verification | solution | `dispatch: speckit.fx-to-dotnet.fix(...)` |
| Deferred work | out-of-scope item | `deferred: <post-migration action>` |

Example output (illustrative):

```
### Layer 1: SDK-Style Conversion

- [ ] [MIG-001] [P0] Convert LibraryA.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(src/LibraryA/LibraryA.csproj)
- [ ] [MIG-002] [P0] Convert LibraryB.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(src/LibraryB/LibraryB.csproj)

### Layer 2: Package Updates

- [ ] [MIG-003] [P0] Apply package chunk 1 to LibraryA (3 minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryA/LibraryA.csproj, chunk=1)
- [ ] [MIG-004] [P0] Apply package chunk 2 to LibraryA (1 major update) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryA/LibraryA.csproj, chunk=2)
- [ ] [MIG-005] [P0] Apply package chunk 1 to LibraryB (2 minor updates) — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryB/LibraryB.csproj, chunk=1)

### Layer 3: Multitarget Libraries

- [ ] [MIG-006] [P0] Multitarget LibraryA to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(src/LibraryA/LibraryA.csproj)
- [ ] [MIG-007] [P0] Multitarget LibraryB to net10.0 — dispatch: speckit.fx-to-dotnet.multitarget-migrate(src/LibraryB/LibraryB.csproj)

### Layer 4: Web App Migration

- [ ] [MIG-008] [P0] Web migrate WebApp slice=bootstrap — dispatch: speckit.fx-to-dotnet.web-migrate(src/WebApp/WebApp.csproj, slice=bootstrap)
- [ ] [MIG-009] [P0] Web migrate WebApp slice=controllers — dispatch: speckit.fx-to-dotnet.web-migrate(src/WebApp/WebApp.csproj, slice=controllers)

### Layer 5: Build Verification

- [ ] [MIG-010] [P0] Solution build verification — dispatch: speckit.fx-to-dotnet.fix(solution)

### Layer 6: Deferred Work

- [ ] [MIG-011] [P2] EF6 → EF Core upgrade (deferred — post-migration) — deferred: Upgrade EntityFramework 6.x to EF Core 9; replace DbContext initialization and remove legacy migrations
- [ ] [MIG-012] [P2] OWIN Identity → ASP.NET Core Identity (deferred — post-migration) — deferred: Replace Microsoft.Owin.Security.* with ASP.NET Core Identity middleware; update cookie configuration
```

## 6. Validate trailers

Before writing, validate every emitted `[MIG-*]` line against one of the two allowed patterns:

**Dispatch tasks** (Layers 1–5):
```
^- \[ \] \[MIG-\d{3}\] \[P[0-3]\] .+ — dispatch: speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$
```

**Deferred tasks** (Layer 6):
```
^- \[ \] \[MIG-\d{3}\] \[P[0-3]\] .+ — deferred: .+$
```

If any line fails both patterns, do not write — exit non-zero with the offending line. A task matching neither pattern is a malformed emission; do not silently skip it.

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
- If a `## Phase \d+: .NET Framework Migration` heading already exists, do NOT renumber other phases again on subsequent runs.
- Never renumber `US*.T*` IDs; renumber only `## Phase N:` heading numbers, and only for phases at or after the insertion point.
- The dedupe pass operates on UNCHECKED non-`[MIG]` tasks only. Never remove a `[MIG]` row, a checked task, or anything from the user-story phases.
- The `> **Extension-managed**` blockquote line is the section's identity anchor — preserve it verbatim.
- The Setup phase (and any Foundational phase) MUST remain ahead of the Migration phase at all times. If a future run detects that Migration has somehow landed before Setup/Foundational, treat it as a parse error and exit non-zero rather than silently rewriting.
</idempotency-rules>

<silent-exit-rules>
- No Framework projects detected → exit 0 with no edits.
- An empty `{featureDir}/migration/plan.md` (no dispatch units) → exit 0 with no edits.
</silent-exit-rules>
