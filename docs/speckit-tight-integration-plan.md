# Plan: Tight Spec-Kit Integration for fx-to-dotnet Extension

**Status**: Draft — Pending Review
**Date**: April 30, 2026
**Supersedes**: [docs/sdd-integration-plan.md](sdd-integration-plan.md), portions of [docs/workflow-plan.md](workflow-plan.md)

---

## Goal

Extend the existing `fx-to-dotnet` Spec-Kit extension so .NET Framework migrations are owned end-to-end by the extension within the standard `specify → plan → tasks → implement` lifecycle, with these contracts:

1. `speckit.plan` — migration content in `plan.md` is produced and owned by the extension; core agents are guided not to emit competing migration plans.
2. The extension integrates into the SDD documents (`spec.md`, `plan.md`, `tasks.md`) via additive, marked sections.
3. **Assessment and migration planning must be complete before `speckit.implement` is allowed to run.** The `assess` and `plan` extension commands run as mandatory hooks during `speckit.plan` (and `speckit.tasks`); `speckit.implement` refuses to proceed until their outputs (`.specify/migration/analysis.md`, `.specify/migration/plan.md`, and `[MIG-*]` tasks in `tasks.md`) are present.
4. Migrations execute **first**, before any user-story implementation.
5. `speckit.implement`, when executing migration items, **only** invokes commands/workflows from the `fx-to-dotnet` extension.
6. Each migration change is **reviewed by the user** before it is applied.

---

## Current State (Verified)

### Extension on disk
- `fx-to-dotnet` v0.3.0; `fx-to-dotnet/extension.yml` declares 11 core commands + 6 workflows.
- **No `hooks:` section in `extension.yml`.**
- **No hook command files exist** (`specify-hook`, `plan-hook`, `tasks-hook`, `implement-hook`, `verify-hook` referenced in `docs/sdd-integration-plan.md` were never created).
- Workflows present: `assess-and-plan`, `sdk-normalize`, `package-modernize`, `package-update`, `library-plan`, `web-app-migration`. **Missing**: `library-update` (referenced in `docs/workflow-plan.md`).

### Spec-Kit integration surfaces (verified in `C:\spec-kit-main\spec-kit-main`)

| Surface | Capability | Limit |
|---|---|---|
| **Hooks** (`extensions/EXTENSION-API-REFERENCE.md`) | `before/after_{specify,plan,tasks,implement}`. `optional: false` blocks parent. Core agents are instructed to "Wait for the result of the hook command before proceeding." | Cannot mutate parent command output directly — only side-effect via files. |
| **Presets** (`presets/ARCHITECTURE.md`) | Can REPLACE core command bodies (`speckit.plan`, `speckit.tasks`, `speckit.implement`) and template files. | Resolution order: `.specify/templates/overrides/` → presets → extensions → core. |
| **Extension commands** | Namespaced, callable from hooks/workflows. | Pattern enforces 3+ dot segments — cannot shadow core `speckit.plan`. |

This means: **a hook alone cannot prevent core from generating migration content** — only a preset (or annotation markers the AI is asked to respect) can do that. So tight integration requires a layered approach.

---

## Design — Six Layers

Each layer is independently usable. The full stack delivers tight integration. Layers 1–3 are required; Layer 4 (preset) is opt-in but closes the last gap; Layers 5–6 round out the workflow inventory and review semantics.

### Layer 1 — Hook registration (`extension.yml`)

Add `hooks:` section. **Four** hooks are mandatory (`optional: false`) so that assessment and planning are guaranteed complete before `speckit.implement` can begin:

| Event | Command | optional | Role |
|---|---|---|---|
| `after_specify` | `speckit.fx-to-dotnet.specify-hook` | **`false`** | **Mandatory.** Detect Framework projects; annotate `spec.md`. Idempotent and silent-exits on non-Framework workspaces, so it is safe to run unconditionally. Mandatory because spec-kit core only auto-executes hooks marked `optional: false`. |
| `after_plan` | `speckit.fx-to-dotnet.plan-hook` | **`false`** | **Mandatory.** Run `assess` + `plan`; produce `.specify/migration/analysis.md` and `.specify/migration/plan.md`; annotate SDD docs. Silent-exit with success if no Framework project detected. |
| `after_tasks` | `speckit.fx-to-dotnet.tasks-hook` | **`false`** | **Mandatory.** Insert `[MIG]` tasks **before** user-story phases; dedupe; declare dependencies. Silent-exit on non-Framework solutions. |
| `before_implement` | `speckit.fx-to-dotnet.implement-hook` | **`false`** | **Mandatory gate.** Verify assessment+plan artifacts exist; refuse to proceed otherwise. Then dispatch each `[MIG]` task to its mapped extension command with per-task review. Do not return until all `[MIG]` resolved. |
| `after_implement` | `speckit.fx-to-dotnet.verify-hook` | `true` | Verify build; annotate plan.md/tasks.md with verification status. |

The combination of mandatory `after_plan` + `after_tasks` + `before_implement` enforces **goal 3**: assessment and migration planning must be complete before any implementation begins. `before_implement` is the failsafe — even if a user skips `/speckit.plan` or `/speckit.tasks`, the implement hook detects missing artifacts and blocks.

### Layer 2 — Hook command files

Five new markdown command files under `fx-to-dotnet/commands/hooks/`. All idempotent; silent-exit when no Framework project is detected.

#### `specify-hook.md`
- Run project detection.
- If any project is .NET Framework, append `## Migration Context Detected` to `spec.md` with a `> **Extension-managed**` blockquote directive.
- Write `.specify/migration/detection.md`.

#### `plan-hook.md`
- Invoke `speckit.fx-to-dotnet.assess` then `speckit.fx-to-dotnet.plan`.
- Append `## Migration Assessment Summary` to `spec.md` and `## .NET Migration Plan` to `plan.md`, both wrapped with `> **Extension-managed** — do not generate tasks from this section…` directive blockquotes (Layer 4 alone enforces this; markers are belt-and-suspenders).

#### `tasks-hook.md`
The most invasive hook. Edits `tasks.md`:

1. **Dedupe pass**: scan unchecked non-`[MIG]` tasks for migration keywords (`SDK conversion`, `SDK-style`, `multitarget`, `package update`, `NuGet update`, `framework migration`, `migrate to .NET`, etc.). Remove matches and renumber following tasks.
2. **Insertion**: locate the first `## Phase N: ... User Story` heading and insert a new `## Phase N: .NET Framework Migration` block immediately before it; renumber subsequent phases. Fallback to append-at-end if no user-story phases exist.
3. **Granular `[MIG]` task emission**: one task per granular dispatch unit. Each line carries a machine-readable trailer (see Layer 3):
   ```
   - [ ] [MIG-001] [P0] Convert ProjectA.csproj to SDK-style — dispatch: speckit.fx-to-dotnet.convert(ProjectA.csproj)
   - [ ] [MIG-002] [P0] Apply package chunk 1 to LibraryA (3 minor updates)   — dispatch: speckit.fx-to-dotnet.update-packages(project=src/LibraryA/LibraryA.csproj, chunk=1)
   - [ ] [MIG-003] [P0] Multitarget LibraryA to net10.0         — dispatch: speckit.fx-to-dotnet.library-update(LibraryA.csproj)
   - [ ] [MIG-004] [P0] Web migrate WebApp (slice: bootstrap)   — dispatch: speckit.fx-to-dotnet.web-app-migration(WebApp.csproj, slice=bootstrap)
   ```
4. **Dependency note**: append `### Dependencies — All [US*] tasks depend on completion of all [MIG-*] tasks.`

#### `implement-hook.md` — **the gate** (satisfies goals 3, 4, 5, 6)

```
1. Detect migration context (read .specify/migration/detection.md OR re-run detect)
   • If no Framework projects → silent-exit success (non-Framework solutions unaffected)

2. PRECONDITION CHECK — assessment and plan MUST be complete:
   a. Verify .specify/migration/analysis.md exists (assess output)
   b. Verify .specify/migration/plan.md exists (plan output) and has phase sections
   c. Verify tasks.md contains at least one [MIG-*] task
   d. If ANY check fails → exit NON-ZERO with a clear remediation message:
        "Migration assessment and plan must complete before implement.
         Missing: <list>. Run `/speckit.plan` then `/speckit.tasks`,
         or invoke `speckit.fx-to-dotnet.assess-and-plan` directly."
      (Mandatory hook → core blocks speckit.implement.)

3. Resume check from .specify/migration/implement-state.md

4. Parse tasks.md → ordered list of unchecked [MIG-*] tasks

5. For each task:
   a. Show task summary + planned-changes preview to user
   b. Per-task review prompt: approve | skip | abort | autoApprove-rest
   c. If approve: validate dispatch target matches ^speckit\.fx-to-dotnet\.
                  invoke the mapped command/workflow; wait for completion
   d. On success: mark [X], log to implement-state.md
   e. On failure: retry | skip | abort
   f. If skip: mark [~] with comment
   g. If abort: stop, exit non-zero, leave remaining unchecked

6. After all [MIG] resolved:
   - Append "## Migration Execution Summary" to plan.md
   - Insert "> ✓ Migration Complete" checkpoint in tasks.md above first [US*]
   - Hook exits → core resumes implement for [US*] only
```

Three security/contract guarantees:
- The **precondition check** (step 2) blocks `speckit.implement` whenever assessment or plan artifacts are missing. This is the technical enforcement of **goal 3 (assessment + plan before implement)**.
- The dispatch validator **rejects** any target that does not match `^speckit\.fx-to-dotnet\.`. This is the technical enforcement of **goal 5 (only the custom extension or workflows)**.
- The gate **always pauses on build failure** even under `autoApprove-rest` (carried from `docs/workflow-plan.md`).

#### `verify-hook.md`
- Invoke `speckit.fx-to-dotnet.fix` for solution build.
- Write `.specify/migration/completion.md`.
- Append `### Migration Verification` summaries to `plan.md` and the `## .NET Framework Migration` section of `tasks.md`.

### Layer 3 — `[MIG]` dispatch map

A simple, reviewable contract embedded in every `[MIG-*]` task line:

```
— dispatch: speckit.fx-to-dotnet.<command>(<args>)
```

`tasks-hook` produces; `implement-hook` parses and validates. The prefix check is the technical mechanism that satisfies goal 4.

### Layer 4 — Companion Preset (closes the last gap on goal 1)

New folder `fx-to-dotnet/` (sibling to `fx-to-dotnet/` in repo root) shipped from the same repo, installable independently:

- `preset.yml` — manifest, `speckit_version: ">=0.7.2"`.
- `templates/commands/tasks.md` (override) — adds: "If `.specify/extensions.yml` enables `fx-to-dotnet`, do NOT generate migration-themed tasks. Emit only a placeholder `## Phase N: .NET Framework Migration (extension-managed)` heading; the `after_tasks` hook will populate it."
- `templates/commands/implement.md` (override) — adds: "Do not interpret or dispatch `[MIG-*]` tasks yourself; the `before_implement` hook handles them. Do not dispatch any non-`speckit.fx-to-dotnet.*` command for migration items."
- `templates/plan-template.md` (override) — adds a "Migration Gate" subsection inside Constitution Check for .NET Framework projects.

This is the only mechanism that **prevents core from emitting migration content at the source**, satisfying goal 1 fully. Hooks plus annotation markers (Layers 1–3) come close but rely on AI cooperation; the preset is deterministic.

### Layer 5 — New workflows

Complete the migration toolset (referenced but not implemented in `docs/workflow-plan.md`):

- `commands/workflows/library-update/workflow.yml` — single-library multitarget + fix; called per-library by `library-plan` and per-`[MIG]`-task by `implement-hook`.

The existing monolithic `orchestrate` command remains the single-call full-chain entry point; `implement-hook` falls back to invoking it directly when `tasks.md` lacks `[MIG-*]` tasks.

### Layer 6 — Per-change review semantics (goal 6)

Per-task review = per granular unit:

| Change type | Granularity | Tasks emitted |
|---|---|---|
| SDK conversion | per project | 1 `[MIG]` per legacy project |
| Package updates | per chunk | 1 `[MIG]` per planned chunk |
| Multitarget | per library | 1 `[MIG]` per non-web project |
| Web migration | per slice | 1 `[MIG]` per slice (bootstrap, controllers, auth, …) |

Outer review gate lives in `implement-hook`. Existing `gate` steps inside workflows (`workflow.yml` files) continue to fire on build failure even when the user picks `autoApprove-rest` for the outer loop.

### Layer 7 — Policy-loading enforcement (verifiable policy application)

**Problem.** Migration domain policies (`ef6-migration-policy`, `systemweb-adapters`, `owin-identity`, `windows-service-migration`) and infrastructure policies (`dependency-layers`, `nuget-package-compat`) are referenced inside `assess.md` and `plan.md` with soft language ("consult", "follow", "via X policy"). The `plan-hook` only verifies that output files exist — not that those policies actually shaped the output. A skipped policy is indistinguishable from an applied one.

**Approach.** Treat policy loading as an *output-contract* problem, enforced at three layers so failure is observable from the artifact alone:

1. **Command-level — mandatory load directives.** Every soft "consult/follow/via" reference to a policy in `assess.md` and `plan.md` is converted to an explicit ⛔ MANDATORY `get_instructions(kind='policy', query='<policy-name>')` call, matching the pattern already used at `assess.md` line 91 for `scenario-initialization`. Each command file gets a `## Required Policies` preamble (after `## Constraints`) listing all policies it must load before any work begins, so loading is front-loaded rather than buried in step prose.

2. **Output contract — `## Policies Applied` table.** The `analysis.md` template (in `assess.md`) and the plan output structure (in `plan.md`) gain a fixed `## Policies Applied` section with one row per required policy:

   | Policy | Source | Applied To | Outcome |
   |---|---|---|---|
   | `ef6-migration-policy` | `policies/ef6-migration-policy/POLICY.md` | 3 projects with `EntityFramework` references | Retained per rule 1; flagged as post-migration item |
   | `windows-service-migration` | `policies/windows-service-migration/POLICY.md` | none — no `ServiceBase` matches | n/a |

   Policies with no applicable code still get a row with "no matches in solution" — the row's *presence* is the proof of loading.

3. **Hook-level verification gate.** `plan-hook.md` gains a new step (between current step 3 and step 4): after `assess` and `plan` complete, the hook reads both output files, parses each `## Policies Applied` table, and verifies every policy in the canonical required-policies list appears. On miss it exits non-zero with `Required policy '<name>' not cited in '.specify/migration/<file>'. Re-run after ensuring 'speckit.fx-to-dotnet.<command>' loads and applies it.` This propagates failure up through the mandatory `after_plan` contract, blocking `speckit.plan` until policies are demonstrably applied. Verification runs **after** the non-Framework silent-exit guard, so non-migration workspaces remain unaffected.

**Canonical required-policies list** (lives inline in `plan-hook.md`):

| Command | Output file | Required policies |
|---|---|---|
| `speckit.fx-to-dotnet.assess` | `.specify/migration/analysis.md` | `dependency-layers`, `nuget-package-compat`, `ef6-migration-policy`, `systemweb-adapters`, `owin-identity`, `windows-service-migration` |
| `speckit.fx-to-dotnet.plan` | `.specify/migration/plan.md` | `dependency-layers`, `windows-service-migration` |

Promote to a new `required_policies:` field under `provides.commands[*]` in `extension.yml` later if a second hook needs the same data; not needed initially.

**Idempotency.** The `## Policies Applied` section is replaced (not appended) on rerun, matching the existing extension-managed-section idempotency rules in `plan-hook`.

### Layer 8 — Shared analysis artifact location

**Problem.** The assessment artifact `analysis.md` originally lived under `.fx-to-dotnet/`, an extension-private state directory. Core Spec Kit commands (`/speckit.plan`, `/speckit.analyze`, `/speckit.verify`) cannot discover content under arbitrary extension folders, so the file is reachable only by hooks and other `fx-to-dotnet` commands. This makes `analysis.md` an *opaque* dependency from Spec Kit's point of view and blocks any future SDD command from consuming the migration assessment directly.

**Approach.** Relocate the assessment output to **`.specify/migration/analysis.md`**, under Spec Kit's canonical `.specify/` root, namespaced `migration/` to avoid collision with feature-scoped artifacts under `specs/{branch}/`.

- **Producer**: `speckit.fx-to-dotnet.assess` writes to the new path; the existing `## Policies Applied` template (Layer 7) is preserved verbatim — only the file path changes.
- **Consumers**: `plan-hook`, `implement-hook`, `orchestrate`, and any future core Spec Kit command (`/speckit.analyze`, `/speckit.verify`) read from the new path. At the time of this layer, all other migration state files (`plan.md`, `package-updates.md`, `preferences.md`, per-project `{ProjectName}.md`) remained under `.fx-to-dotnet/` (see Open Questions; subsequently relocated — all migration state now lives under `.specify/migration/`).
- **Discovery**: `extension.yml` v1.0 schema does **not** expose a `provides.artifacts` node, and `provides.config` is reserved for config-file templates (incompatible semantics — a runtime output is not a template). Decision: register the path **by convention** — document `.specify/migration/analysis.md` in a top-of-file comment block in `extension.yml` and add a `shared-artifact` tag. The path itself is the contract; Spec Kit hooks and any future core consumer locate the file by the conventional path. *(Resolves Open Question 7 below.)*
- **Backward compatibility**: none — single-shot path migration. Users with an in-flight migration carrying an existing `.fx-to-dotnet/analysis.md` must move the file once; the changelog will call this out.
- **Version**: extension version bumps to `0.5.0` (breaking path change).

**Why only `analysis.md`.** It is the only assessment artifact whose content has cross-extension consumer value (policies-applied evidence, project classifications, dependency layers). The other state files (then under `.fx-to-dotnet/`) tracked in-flight extension execution state and had no current external consumer; relocating them was deferred (Open Question 6) and ultimately performed in a later iteration.

---

## Data Flow

```
speckit.specify
  └─► after_specify hook (specify-hook)
       ├─ Writes .specify/migration/detection.md
       └─ Appends "## Migration Context Detected" to spec.md (extension-managed marker)

speckit.plan
  └─► after_plan hook (MANDATORY — plan-hook)
       ├─ Invokes assess → .specify/migration/analysis.md, .specify/migration/package-updates.md
       ├─ Invokes plan   → .specify/migration/plan.md
       ├─ Appends "## Migration Assessment Summary" to spec.md
       └─ Appends "## .NET Migration Plan" to plan.md
       (Mandatory: speckit.plan does not return success until assess+plan complete.
        Silent-exit on non-Framework solutions.)

speckit.tasks
  ├─ (with preset) Core skips migration content; emits placeholder heading only
  └─► after_tasks hook (MANDATORY — tasks-hook)
       ├─ Dedupes any migration-themed tasks core emitted
       ├─ INSERTS "## Phase N: .NET Framework Migration" BEFORE user stories
       ├─ Emits granular [MIG-*] tasks each with `dispatch:` trailer
       └─ Renumbers subsequent phases

speckit.implement
  └─► before_implement hook (MANDATORY — implement-hook)
       │ PRECONDITION: verify .specify/migration/analysis.md AND .specify/migration/plan.md exist
       │                AND tasks.md contains [MIG-*] tasks
       │ If missing → exit non-zero with remediation message; core blocks.
       │
       │ For each unchecked [MIG-*] task in order:
       │   • show preview
       │   • per-task review (approve | skip | abort | autoApprove-rest)
       │   • validate dispatch target ^speckit\.fx-to-dotnet\.
       │   • invoke mapped extension command/workflow
       │   • mark [X] / [~] / leave unchecked
       │ Append "## Migration Execution Summary" to plan.md
       └ Insert "> ✓ Migration Complete" checkpoint above first [US*] in tasks.md
  └─► (core implement now processes [US*] tasks only)
  └─► after_implement hook (verify-hook)
       ├─ Solution build
       ├─ Writes .specify/migration/completion.md
       ├─ Appends "### Migration Verification" to plan.md
       └─ Appends verification note to tasks.md migration section
```

---

## Files Changed / Created

| File | Action | Purpose |
|---|---|---|
| `fx-to-dotnet/extension.yml` | Edit | Bump to 0.5.0; register 5 hook commands + 1 new workflow; add `hooks:` section; register `.specify/migration/analysis.md` as a shared artifact (Layer 8). |
| `fx-to-dotnet/commands/hooks/specify-hook.md` | New | `after_specify` hook. |
| `fx-to-dotnet/commands/hooks/plan-hook.md` | New | `after_plan` hook. |
| `fx-to-dotnet/commands/hooks/tasks-hook.md` | New | `after_tasks` hook (insertion, dedup, dispatch annotations). |
| `fx-to-dotnet/commands/hooks/implement-hook.md` | New | `before_implement` mandatory gate (per-task review, dispatch validation). |
| `fx-to-dotnet/commands/hooks/verify-hook.md` | New | `after_implement` hook. |
| `fx-to-dotnet/commands/assess/assess.md` | Edit (Layer 7, Layer 8) | Add `## Required Policies` preamble; convert soft policy references to mandatory `get_instructions` calls; add `## Policies Applied` to the `analysis.md` template; **repath all `analysis.md` references from `.fx-to-dotnet/` to `.specify/migration/`** (Layer 8). |
| `fx-to-dotnet/commands/initialize/initialize.md` | Edit (Layer 8) | Update directory-tree diagram and project-classifications note for the new `analysis.md` path; ensure `.specify/migration/` is provisioned during init. |
| `fx-to-dotnet/commands/orchestrate/orchestrate.md` | Edit (Layer 8) | Update state diagram, state-files list, post-assess verification, and planner handoff payload references for the new path. |
| `fx-to-dotnet/commands/hooks/implement-hook.md` | Edit (Layer 8) | Update precondition gate to read `.specify/migration/analysis.md` (in addition to the Layer 2 authoring). |
| `fx-to-dotnet/README.md` | Edit (Layer 8) | Repath `analysis.md` references in lifecycle docs and gating-files list. |
| `fx-to-dotnet/commands/plan/plan.md` | Edit (Layer 7) | Add `## Required Policies` preamble; convert soft policy references to mandatory `get_instructions` calls; add `## Policies Applied` to the plan output structure. |
| `fx-to-dotnet/commands/workflows/library-update/workflow.yml` | New | Single-library multitarget+fix (Layer 5). |
| `fx-to-dotnet/preset.yml` | New (Layer 4, optional) | Preset manifest. |
| `fx-to-dotnet/templates/commands/tasks.md` | New (Layer 4) | Override of core tasks command. |
| `fx-to-dotnet/templates/commands/implement.md` | New (Layer 4) | Override of core implement command. |
| `fx-to-dotnet/templates/plan-template.md` | New (Layer 4) | Override with Migration Gate. |
| `fx-to-dotnet/README.md` | Edit | Document the lifecycle and `[MIG]` task semantics. |
| `docs/sdd-integration-plan.md` | Edit | Mark superseded. |
| `docs/workflow-plan.md` | Edit | Mark superseded for `library-update` portions. |

No new scripts required. Existing `scripts/cross-reference-audit.ps1` and `scripts/mcp-config-validate.ps1` cover validation. (User preference: any new scripts ship in both PowerShell and Bash — N/A here.)

---

## Implementation Phases

### Phase 1 — Hook commands (parallelizable)
1. Create `commands/hooks/` directory.
2. Author `specify-hook.md`, `plan-hook.md`, `tasks-hook.md`, `implement-hook.md`, `verify-hook.md`. Salvage annotation snippets from `docs/sdd-integration-plan.md`.

### Phase 2 — New workflows (parallel with Phase 1)
3. Author `commands/workflows/library-update/workflow.yml` (model: per-library loop in `library-plan/workflow.yml`).

### Phase 3 — Manifest registration (depends on 1–3)
4. Update `extension.yml`: bump version, register 5 + 1 commands, add `hooks:` section with `optional: false` on `after_plan`, `after_tasks`, **and** `before_implement`.

### Phase 4 — Companion preset (depends on Phase 3; optional)
5. Create `fx-to-dotnet/preset.yml`.
6. Create three template overrides.

### Phase 5 — Verification & docs
7. Update `fx-to-dotnet/README.md`.
8. Mark prior planning docs superseded.
9. Run `scripts/cross-reference-audit.ps1` and `scripts/mcp-config-validate.ps1`.

### Phase 6 — Shared analysis artifact relocation (Layer 8; depends on Phase 1–3, parallel with Phase 4–5)
10. Verify `extension.yml` v1.0 schema supports a shared-artifact registration node; choose `provides.artifacts` or `provides.config` fallback.
11. Update `extension.yml`: bump `0.4.0` → `0.5.0`; register `.specify/migration/analysis.md` as a shared artifact.
12. Repath every `.fx-to-dotnet/analysis.md` reference (producer, consumers, hooks, orchestrator, README, integration docs) to `.specify/migration/analysis.md`. Add directory-create instruction to producer.
13. Workspace-wide grep for `\.fx-to-dotnet[/\\]analysis` must return zero matches; `\.specify/migration/analysis\.md` must appear in producer + consumers + docs.
14. Update `scripts/cross-reference-audit.{ps1,py}` if it hard-codes the old path.

---

## Verification

1. **Manifest**: `pwsh scripts/cross-reference-audit.ps1` passes; YAML loads cleanly.
2. **Naming**: every command name and every dispatch annotation matches `^speckit\.fx-to-dotnet\.[a-z0-9-]+$`.
3. **End-to-end** on a small Framework solution:
   - `/speckit.specify` → confirm `## Migration Context Detected` appears in `spec.md` with marker.
   - `/speckit.plan` → confirm `## .NET Migration Plan` appears in `plan.md` AND that `.specify/migration/analysis.md` and `.specify/migration/plan.md` exist (mandatory `after_plan` produced them).
   - `/speckit.tasks` → confirm `[MIG-*]` tasks appear **before** the first `## Phase *: User Story`, every `[MIG]` row has a `dispatch:` trailer, no core-generated migration duplicates remain.
   - `/speckit.implement` → confirm hook prompts per `[MIG]` task; approve some, skip one, choose `autoApprove-rest`; confirm only `speckit.fx-to-dotnet.*` commands invoked; confirm `[X]` marks; confirm `## Migration Execution Summary` appended; confirm core only proceeds to `[US*]` after all `[MIG]` resolved.
4. **Precondition enforcement (goal 3)**: on a Framework solution, delete `.specify/migration/plan.md` and run `/speckit.implement` directly. Confirm `implement-hook` exits non-zero with the remediation message and `speckit.implement` does not proceed. Repeat with `tasks.md` containing no `[MIG-*]` rows — same result.
5. **Negative**: on a modern .NET solution, all 5 hooks silent-exit (no edits to any SDD doc). Confirm mandatory `after_plan`/`after_tasks`/`before_implement` do NOT block when no Framework project is present.
5a. **Shared artifact location (Layer 8)**: after `/speckit.plan` on a Framework solution, confirm `.specify/migration/analysis.md` exists (not `.fx-to-dotnet/analysis.md`). Confirm `extension.yml` registration is parseable. Confirm `/speckit.analyze` (core Spec Kit) can locate the file by convention without extension-specific knowledge.
6. **Idempotency**: re-running any hook leaves no duplicate sections (anchor: `> **Extension-managed**` blockquote).
7. **Preset opt-in** (Layer 4): with preset installed, core `/speckit.tasks` produces only the placeholder migration heading.
8. **Security**: try a hand-edited `[MIG]` task with `dispatch: speckit.evil.cmd(...)`; confirm `implement-hook` rejects it.

---

## Decisions

| Decision | Rationale |
|---|---|
| Annotation-only ownership of plan content (per user choice) | Keeps diffs reviewable; preset (Layer 4) provides the deterministic backstop without forking core. |
| **Three mandatory hooks** (`after_plan`, `after_tasks`, `before_implement` all `optional: false`) | Guarantees assessment + migration plan + `[MIG]` tasks are produced before `speckit.implement` can begin. `before_implement` precondition check is the failsafe if a user invokes implement directly. |
| Mandatory hooks silent-exit on non-Framework solutions | Prevents the mandatory contract from breaking ordinary (non-migration) Spec Kit usage. |
| `dispatch:` annotation on `[MIG]` lines + prefix-validated dispatch | Technical enforcement of goal 5 — implement cannot escape the extension namespace. |
| Per-task review (per user choice) | Implemented as outer loop in `implement-hook`. Inner workflow `gate` steps still fire on build failure. |
| Companion preset shipped in same repo, installed separately | Co-versioned for safety; opt-in for users who want soft integration only. |
| Hook files under `commands/hooks/` | Separation from atomic phase commands; aligns with the existing `commands/workflows/` convention. |
| `analysis.md` relocated to `.specify/migration/analysis.md` (Layer 8) | Spec Kit core only discovers content under `.specify/`; relocating makes the assessment a first-class shared artifact consumable by `/speckit.analyze` and `/speckit.verify` without extension-private knowledge. Single-shot path migration; no backward-compat shim. Sibling state files (`plan.md`, `package-updates.md`, `preferences.md`, per-project state) initially stayed under `.fx-to-dotnet/` for this iteration; they were relocated to `.specify/migration/` in a later iteration. |
| Excluded | Modifying spec-kit core; replacing `speckit.implement` entirely; new MCP tools; changes to existing 7-phase logic; relocating non-`analysis.md` state files. |

---

## Open Questions for Reviewer

1. **Hook directory layout**: `commands/hooks/*.md` (recommended) vs flat `commands/*.md` (matches paths in the older `docs/sdd-integration-plan.md`)?
2. **Preset packaging**: ship `fx-to-dotnet/` in this repo (recommended), separate repo, or skip the preset entirely (Layers 1–3 + 5–6 only)?
3. **`autoApprove-rest` persistence**: current-run-only (recommended) or persist to `.specify/migration/preferences.md` with a `--remember` opt-in?
4. **Granularity of web slices**: emit one `[MIG]` per slice (recommended for true per-change review) or one `[MIG]` for the whole web migration with internal gates? The first is more reviewable but produces more tasks.
5. **Version bump**: 0.3.0 → 0.4.0 (Layers 1–7 additive features) or 0.4.0 → 0.5.0 (Layer 8 adds breaking path change for `analysis.md`, recommended)?
6. **Sibling artifact relocation (resolved in v0.6.0 and a later iteration)**: `plan.md` and the orchestrator state file (renamed to `orchestration.md`) were relocated to `.specify/migration/` in v0.6.0, alongside `analysis.md`. Remaining private files (`package-updates.md`, `preferences.md`, `detection.md`, `implement-state.md`, `completion.md`, per-project `{ProjectName}.md`) were subsequently relocated to `.specify/migration/` as well; the extension-private `.fx-to-dotnet/` directory is no longer used.
7. **`extension.yml` schema** (resolved during T027): v1.0 has no `provides.artifacts` node and `provides.config` is for config-file templates only. Layer 8 documents the path by convention in a `extension.yml` comment block and a `shared-artifact` tag — no schema change needed.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Core agent ignores `> **Extension-managed**` markers and re-emits migration tasks | Medium (without preset), Low (with preset) | Duplicate tasks in `tasks.md` | Layer 4 preset; `tasks-hook` dedupe pass. |
| User picks `autoApprove-rest` and a silent breaking change ships | Low | Broken build | Build failures always pause; per-task `[X]` and `implement-state.md` provide audit trail. |
| Mandatory `after_plan`/`after_tasks` blocks `/speckit.plan` or `/speckit.tasks` on non-Framework solutions | Low | Lifecycle broken for unrelated projects | All three mandatory hooks **silent-exit success** when no Framework project detected (`.specify/migration/detection.md` empty or absent + re-detect returns none). |
| User runs `/speckit.implement` without first running plan/tasks | Medium | Would otherwise skip migration | `before_implement` precondition check exits non-zero with remediation; core blocks. |
| `dispatch:` trailer hand-edited to a malicious target | Very Low | Arbitrary command exec | Prefix validator in `implement-hook`. |
| Renumbering during `tasks-hook` insertion misaligns user-edited task IDs | Medium | Stale references in user notes | Use phase-relative IDs (`US1.T01`) where possible; document the renumbering behavior. |

---

## Layer 9 — Per-Feature Migration Artifacts (v0.7.0)

**Approach.** Relocate every migration artifact from the workspace-root `.specify/migration/` directory into the active Spec Kit feature folder at `{featureDir}/migration/` (i.e. `specs/<branch>/migration/`), so all hook-created files sit alongside `spec.md`, `plan.md`, and `tasks.md`. Hard cut, no backward-compat shim (mirrors the prior `.fx-to-dotnet/` → `.specify/migration/` cuts in v0.5.0/v0.6.0).

**Rationale.** Spec Kit's lifecycle artifacts are per-feature (per branch). Pinning migration state to the workspace root forced a single migration scope across all branches; switching feature branches mid-migration could cause state to be silently shared or overwritten. Per-feature scoping matches Spec Kit's per-branch isolation model and makes the artifacts naturally discoverable by core (`/speckit.analyze`, `/speckit.verify`) — which already operates on the active feature dir.

**Resolution of `{featureDir}`.** Hooks and commands resolve the active feature folder in this order:
1. `SPECIFY_FEATURE` env var if set
2. Current git branch matching `^[0-9]+-` against `specs/<branch>/`
3. Single feature folder under `specs/` if exactly one exists
4. Otherwise: mandatory hooks silent-exit success; `initialize` and direct commands stop and ask the user.

**Files relocated.** `analysis.md`, `plan.md`, `orchestration.md`, `package-updates.md`, `preferences.md`, `detection.md`, `implement-state.md`, `completion.md`, per-project `{ProjectName}.md` — all move from `.specify/migration/` to `{featureDir}/migration/`.

**Updated touchpoints.** `extension.yml` (header comments + version 0.7.0); `commands/initialize/initialize.md` (path conventions + `featureDir` resolution); all five hooks under `commands/hooks/`; producers (`detect`, `assess`, `plan`, `orchestrate`); per-project state writers (`package-compat`, `build-fix`, `multitarget`, `web-migrate`, `sdk-convert`); workflow review-prompt strings; `fx-to-dotnet/templates/plan-template.md` artifact table; `fx-to-dotnet/README.md` lifecycle and state-files sections.

**Verification.** Workspace-wide grep for `\.specify/migration/` over `fx-to-dotnet/**` and `presets/**` returns zero matches. Each producer and consumer references `{featureDir}/migration/` instead. Smoke test on a Framework solution confirms each artifact lands under `specs/<branch>/migration/`.
