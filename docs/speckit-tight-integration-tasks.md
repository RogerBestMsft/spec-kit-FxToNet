# Tasks: Tight Spec-Kit Integration for fx-to-dotnet Extension

**Status**: Draft — Pending Review
**Date**: April 30, 2026
**Source plan**: [docs/speckit-tight-integration-plan.md](speckit-tight-integration-plan.md)

Task IDs are stable across phases; `[P]` denotes tasks safe to run in parallel within a phase.
Each task lists the files it touches and the acceptance signal that proves it is done.

---

## Phase 1 — Hook command authoring (parallelizable)

> Salvage annotation snippets and pseudo-code from [docs/Old/sdd-integration-plan.md](Old/sdd-integration-plan.md).
> All hook commands are idempotent and **silent-exit success** when project detection finds no .NET Framework projects.

### T001 [P] Create hooks directory
- Create folder: `fx-to-dotnet/commands/hooks/`
- **Done when**: directory exists and is tracked.

### T002 [P] Author `specify-hook.md` (after_specify, optional)
- File: `fx-to-dotnet/commands/hooks/specify-hook.md`
- Behavior:
  - Invoke `speckit.fx-to-dotnet.detect`.
  - If any .NET Framework project found, write `.specify/migration/detection.md` and append `## Migration Context Detected` to `spec.md` wrapped in a `> **Extension-managed**` blockquote.
  - Otherwise silent-exit success.
- **Done when**: file exists; idempotent re-run produces no duplicate sections.

### T003 [P] Author `plan-hook.md` (after_plan, mandatory)
- File: `fx-to-dotnet/commands/hooks/plan-hook.md`
- Behavior:
  - Invoke `speckit.fx-to-dotnet.assess` then `speckit.fx-to-dotnet.plan`.
  - Append `## Migration Assessment Summary` to `spec.md` and `## .NET Migration Plan` to `plan.md`, both inside `> **Extension-managed** — do not generate tasks from this section…` directive blockquotes.
  - Silent-exit success on non-Framework solutions.
- **Done when**: hook produces `.specify/migration/analysis.md` and `.specify/migration/plan.md` and the two annotated sections; non-zero exit only on assess/plan failure.

### T004 [P] Author `tasks-hook.md` (after_tasks, mandatory)
- File: `fx-to-dotnet/commands/hooks/tasks-hook.md`
- Behavior (in order):
  1. **Dedupe**: scan unchecked non-`[MIG]` tasks for migration keywords (`SDK conversion`, `SDK-style`, `multitarget`, `multi-target`, `package update`, `NuGet update`, `framework migration`, `migrate to .NET`, `convert to SDK`, `update target framework`, `web migration`, `web migrate`, `build verification`, `build fix`, `System.Web`, `OWIN`); remove matches; renumber following tasks.
  2. **Insert** `## Phase N: .NET Framework Migration` immediately before the first `## Phase N: ... User Story` heading; renumber subsequent phases. Fallback to append-at-end if no user-story phases exist.
  3. **Emit** granular `[MIG-*]` tasks (one per dispatch unit per Layer 6 granularity table) each ending in a machine-readable trailer `— dispatch: speckit.fx-to-dotnet.<command>(<args>)`.
  4. Append `### Dependencies — All [US*] tasks depend on completion of all [MIG-*] tasks.`
- Silent-exit success on non-Framework solutions.
- **Done when**: rerun against an already-migrated `tasks.md` produces no duplicates and no further renumbering.

### T005 [P] Author `implement-hook.md` (before_implement, mandatory — **the gate**)
- File: `fx-to-dotnet/commands/hooks/implement-hook.md`
- Behavior:
  1. Detect migration context; silent-exit success if none.
  2. **Precondition check** (goal 3): verify `.specify/migration/analysis.md`, `.specify/migration/plan.md`, and at least one `[MIG-*]` row in `tasks.md`. On failure, exit non-zero with the remediation message specified in the plan.
  3. Read resume state from `.specify/migration/implement-state.md`.
  4. For each unchecked `[MIG-*]` task in order: preview → review prompt (`approve | skip | abort | autoApprove-rest`) → validate `dispatch:` target matches `^speckit\.fx-to-dotnet\.` → invoke mapped command/workflow → mark `[X]` / `[~]` / abort.
  5. After all `[MIG]` resolved: append `## Migration Execution Summary` to `plan.md`; insert `> ✓ Migration Complete` checkpoint above first `[US*]` in `tasks.md`.
- Build failures **always pause** even under `autoApprove-rest`.
- **Done when**: precondition logic, dispatch validator regex, per-task review loop, and resume read/write are all present and documented.

### T006 [P] Author `verify-hook.md` (after_implement, optional)
- File: `fx-to-dotnet/commands/hooks/verify-hook.md`
- Behavior: invoke `speckit.fx-to-dotnet.fix` for solution build; write `.specify/migration/completion.md`; append `### Migration Verification` to `plan.md` and to the `## .NET Framework Migration` section of `tasks.md`.
- **Done when**: file exists and is idempotent.

---

## Phase 2 — New workflow (parallel with Phase 1)

### T007 [P] Author `library-update` workflow
- File: `fx-to-dotnet/commands/workflows/library-update/workflow.yml`
- Single-library multitarget + fix loop; modeled on the per-library section of `commands/workflows/library-plan/workflow.yml`.
- Used by `library-plan` per-library and dispatched by `implement-hook` per `[MIG]` task for libraries.
- Inner `gate` steps must still fire on build failure even under outer `autoApprove-rest`.
- **Done when**: YAML loads cleanly; cross-reference audit passes.

---

## Phase 3 — Manifest registration (depends on T001–T007)

### T008 Register hooks and new workflow in `extension.yml`
- File: `fx-to-dotnet/extension.yml`
- Bump `version` from `0.3.0` to `0.5.0` (Layer 8 introduces a breaking path change for `analysis.md`).
- Register five new commands under `commands:`:
  - `speckit.fx-to-dotnet.specify-hook`
  - `speckit.fx-to-dotnet.plan-hook`
  - `speckit.fx-to-dotnet.tasks-hook`
  - `speckit.fx-to-dotnet.implement-hook`
  - `speckit.fx-to-dotnet.verify-hook`
- Register new workflow `speckit.fx-to-dotnet.library-update`.
- Add `hooks:` section:
  | Event | Command | optional |
  |---|---|---|
  | `after_specify` | `speckit.fx-to-dotnet.specify-hook` | `true` |
  | `after_plan` | `speckit.fx-to-dotnet.plan-hook` | `false` |
  | `after_tasks` | `speckit.fx-to-dotnet.tasks-hook` | `false` |
  | `before_implement` | `speckit.fx-to-dotnet.implement-hook` | `false` |
  | `after_implement` | `speckit.fx-to-dotnet.verify-hook` | `true` |
- **Done when**: `pwsh scripts/cross-reference-audit.ps1` passes; every name matches `^speckit\.fx-to-dotnet\.[a-z0-9-]+$`.

---

## Phase 4 — Companion preset (depends on Phase 3; optional / Layer 4)

### T009 [P] Create preset manifest
- File: `fx-to-dotnet/preset.yml`
- Include `speckit_version: ">=0.7.2"` and a description tying it to `fx-to-dotnet` >= 0.4.0.
- **Done when**: YAML loads cleanly.

### T010 [P] Override `tasks.md` core command
- File: `fx-to-dotnet/templates/commands/tasks.md`
- Add directive: "If `.specify/extensions.yml` enables `fx-to-dotnet`, do NOT generate migration-themed tasks. Emit only a placeholder `## Phase N: .NET Framework Migration (extension-managed)` heading; the `after_tasks` hook will populate it."
- **Done when**: file present and resolution order picks it up before core.

### T011 [P] Override `implement.md` core command
- File: `fx-to-dotnet/templates/commands/implement.md`
- Add directive: "Do not interpret or dispatch `[MIG-*]` tasks yourself; the `before_implement` hook handles them. Do not dispatch any non-`speckit.fx-to-dotnet.*` command for migration items."
- **Done when**: file present.

### T012 [P] Override `plan-template.md`
- File: `fx-to-dotnet/templates/plan-template.md`
- Add a "Migration Gate" subsection inside Constitution Check that lists the precondition artifacts required before `speckit.implement` may run.
- **Done when**: file present.

---

## Phase 5 — Documentation & cleanup (depends on Phase 3)

### T013 Update `fx-to-dotnet/README.md`
- Document the new lifecycle, the five hooks, the `[MIG-*]` task format with `dispatch:` trailer, the precondition gate, and per-task review semantics.
- **Done when**: README references all five hooks and the dispatch contract.

### T014 [P] Mark `docs/Old/sdd-integration-plan.md` superseded
- Add a top-of-file banner pointing to [docs/speckit-tight-integration-plan.md](speckit-tight-integration-plan.md).
- **Done when**: banner present.

### T015 [P] Mark `library-update` portions of `docs/workflow-plan.md` superseded
- Add a banner / inline note clarifying that `library-update` is now delivered per Layer 5 of the tight integration plan.
- **Done when**: banner present.

---

## Phase 6 — Verification (depends on all prior phases)

### T016 Manifest & naming audit
- Run `pwsh scripts/cross-reference-audit.ps1` and `pwsh scripts/mcp-config-validate.ps1`.
- Confirm every command name and every emitted `dispatch:` annotation matches `^speckit\.fx-to-dotnet\.[a-z0-9-]+$`.
- **Done when**: both scripts exit 0.

### T017 End-to-end positive test (Framework solution)
- On a small .NET Framework solution:
  - `/speckit.specify` → `## Migration Context Detected` present in `spec.md`.
  - `/speckit.plan` → `## .NET Migration Plan` in `plan.md` and `.specify/migration/analysis.md` + `.specify/migration/plan.md` exist.
  - `/speckit.tasks` → `[MIG-*]` rows precede first `## Phase N: ... User Story`; every row has a `dispatch:` trailer; no duplicate migration tasks.
  - `/speckit.implement` → per-task prompts; mix of `approve`, `skip`, `autoApprove-rest`; only `speckit.fx-to-dotnet.*` invoked; `## Migration Execution Summary` appended; `[US*]` only proceeds after all `[MIG]` resolved.
- **Done when**: all bullets observed.

### T018 Precondition enforcement test (goal 3)
- On the same Framework solution: delete `.specify/migration/analysis.md`, run `/speckit.implement` directly → confirm non-zero exit + remediation message + core does not proceed.
- Repeat with `tasks.md` containing zero `[MIG-*]` rows → same result.
- **Done when**: both negative cases produce the documented remediation message.

### T019 Negative test (modern .NET solution)
- Run all four lifecycle commands on a non-Framework solution.
- Confirm all five hooks silent-exit success; no SDD docs mutated; mandatory hooks do **not** block.
- **Done when**: lifecycle completes with no `.specify/migration/*` artifacts written.

### T020 Idempotency test
- Re-run each hook against already-annotated SDD docs.
- Confirm no duplicate sections (anchor: `> **Extension-managed**` blockquote) and no `[MIG-*]` renumbering churn.
- **Done when**: second-run diff against first-run is empty.

### T021 Preset opt-in test (Layer 4)
- Install `fx-to-dotnet/`; run `/speckit.tasks` on a Framework solution.
- Confirm core emits only the placeholder `## Phase N: .NET Framework Migration (extension-managed)` heading; `tasks-hook` populates it.
- **Done when**: pre-hook `tasks.md` contains placeholder only; post-hook contains populated `[MIG-*]` rows.

---

## Phase 7 — Policy-loading enforcement (Layer 7)

> Implements [Layer 7 of the plan](speckit-tight-integration-plan.md#layer-7--policy-loading-enforcement-verifiable-policy-application).
> Tasks T022–T024 are parallelizable (different files); T025 depends on T022 and T023; T026 depends on T024 and T025.

### T022 [P] Harden `assess.md` policy loading
- File: `fx-to-dotnet/commands/assess/assess.md`
- Add a `## Required Policies` preamble immediately after the `## Constraints` section listing: `dependency-layers`, `nuget-package-compat`, `ef6-migration-policy`, `systemweb-adapters`, `owin-identity`, `windows-service-migration`. Each entry MUST instruct the agent to call `get_instructions(kind='policy', query='<name>')` before any work begins.
- Convert each existing soft policy reference to an explicit ⛔ MANDATORY load directive matching the line-91 `scenario-initialization` pattern:
  - Line ~125 (`Follow the dependency-layers policy…`)
  - Line ~176 (`from the nuget-package-compat policy`)
  - Line ~204 (`Consult the migration domain policies…`)
  - Line ~213 (`consult the windows-service-migration policy`)
- **Done when**: `grep -n "Consult\|Follow the\|via the .* policy" assess.md` returns no soft references; every named policy appears in a `get_instructions(...)` call.

### T023 [P] Harden `plan.md` policy loading
- File: `fx-to-dotnet/commands/plan/plan.md`
- Add a `## Required Policies` preamble after the `## Constraints` section listing: `dependency-layers`, `windows-service-migration`. Each entry MUST instruct the agent to call `get_instructions(kind='policy', query='<name>')` before any work begins.
- Convert each existing soft policy reference (lines ~34, ~64, ~201) to an explicit ⛔ MANDATORY load directive.
- **Done when**: same grep criterion as T022 satisfied for `plan.md`.

### T024 [P] Extend output templates with `## Policies Applied`
- Files: `fx-to-dotnet/commands/assess/assess.md` (the `analysis.md` template block) and `fx-to-dotnet/commands/plan/plan.md` (the plan output structure block).
- Append a fixed `## Policies Applied` section to each template with columns: `Policy | Source | Applied To | Outcome`. Specify that policies with no matching code in the solution still emit a row with `Applied To = none — no matches in solution` and `Outcome = n/a` — the row's presence is the proof of loading.
- Required policies per file:
  - `analysis.md`: `dependency-layers`, `nuget-package-compat`, `ef6-migration-policy`, `systemweb-adapters`, `owin-identity`, `windows-service-migration`
  - plan output: `dependency-layers`, `windows-service-migration`
- **Done when**: both templates contain a `## Policies Applied` section header with the exact column list and the "no matches" convention documented.

### T025 Add policy-citation verification to `plan-hook.md`
- File: `fx-to-dotnet/commands/hooks/plan-hook.md`
- Insert a new step between the existing step 3 (`Run migration plan`) and step 4 (`Annotate spec.md`) titled `Verify policy citations`.
- Embed the canonical required-policies list inline in the hook (per-command map, matching the table in Layer 7 of the plan).
- Behavior: read `.specify/migration/analysis.md` and `.specify/migration/plan.md`; parse each `## Policies Applied` table; for every policy in the canonical list, verify a row is present. On miss, exit non-zero with the message: `Required policy '<name>' not cited in '<file>'. Re-run after ensuring 'speckit.fx-to-dotnet.<command>' loads and applies it.`
- This step MUST run after the non-Framework silent-exit guard in step 1, so non-migration workspaces remain unaffected.
- Update the `<idempotency-rules>` block to add `## Policies Applied` to the list of extension-managed sections that are replaced (not appended) on rerun.
- **Done when**: the hook contains the verification step and the embedded required-policies map; idempotency rules cover the new section. Depends on T022, T023.

### T026 End-to-end policy-enforcement tests
- Positive: on a Framework solution that uses EF6 and has at least one `ServiceBase` subclass, run `/speckit.plan`. Confirm `.specify/migration/analysis.md` and `.specify/migration/plan.md` each contain a `## Policies Applied` table with all required policies present, including non-applicable ones marked `none — no matches in solution` where appropriate.
- Negative — missing citation: temporarily strip the `## Policies Applied` row for `ef6-migration-policy` from `.specify/migration/analysis.md` and rerun the hook against the same outputs. Confirm `plan-hook` exits non-zero with the documented remediation message and that `speckit.plan` is reported as blocked.
- Negative — non-Framework: run `/speckit.plan` on a pure modern-.NET solution. Confirm the hook still silent-exits 0 (verification gated behind detection), no `.specify/migration/*` artifacts written.
- Idempotency: rerun `/speckit.plan` on the Framework solution; confirm the `## Policies Applied` section is replaced (not duplicated) in both output files.
- **Done when**: all four cases produce the documented behavior. Depends on T024, T025.

---

## Phase 8 — Shared `analysis.md` artifact location (Layer 8)

> Implements [Layer 8 of the plan](speckit-tight-integration-plan.md#layer-8--shared-analysis-artifact-location).
> Single-shot path migration: `.fx-to-dotnet/analysis.md` → `.specify/migration/analysis.md`. No backward-compat shim. T027 unblocks T028; T028–T032 may run in parallel; T033 is the cleanup grep gate; T034 is verification.

### T027 Confirm `extension.yml` schema supports a shared-artifact node
- Inspect Spec Kit `extensions/EXTENSION-API-REFERENCE.md` for `provides.artifacts` (or equivalent).
- Decide between `provides.artifacts` (preferred) and `provides.config` with `shared: true` (fallback).
- **Done when**: a one-line decision recorded in [docs/speckit-tight-integration-plan.md](speckit-tight-integration-plan.md) Layer 8 (replacing the Open Question 7 placeholder) and the chosen YAML snippet drafted for T028.

### T028 Register shared artifact in `extension.yml` and bump version
- File: `fx-to-dotnet/extension.yml`
- Bump `version` from `0.4.0` to `0.5.0` (or update T008's bump to land at `0.5.0` directly).
- Add the shared-artifact registration chosen in T027, pointing at `.specify/migration/analysis.md`.
- **Done when**: YAML loads cleanly; `pwsh scripts/cross-reference-audit.ps1` passes.

### T029 [P] Repath `analysis.md` references in `assess.md` (producer)
- File: `fx-to-dotnet/commands/assess/assess.md`
- Replace every `.fx-to-dotnet/analysis.md` reference with `.specify/migration/analysis.md` (handoff prompt lines, "Persist Assessment Output" step, "analysis.md Template" intro, output format block, resume-check read).
- Add an explicit step before the write: "ensure `.specify/migration/` directory exists".
- **Done when**: `grep -n "\.fx-to-dotnet[/\\]analysis" assess.md` returns zero matches.

### T030 [P] Repath `analysis.md` references in `initialize.md` and `orchestrate.md`
- Files: `fx-to-dotnet/commands/initialize/initialize.md`, `fx-to-dotnet/commands/orchestrate/orchestrate.md`
- Update directory-tree diagrams, "Project classifications live in …" notes, state-files list, post-assess verification note, and orchestrator → planner handoff payload references (`assessmentContent`, `dependencyLayers` source paths) to `.specify/migration/analysis.md`.
- For `initialize.md`: ensure `.specify/migration/` is provisioned during init.
- **Done when**: same grep criterion as T029 satisfied for both files.

### T031 [P] Repath `analysis.md` references in `plan-hook.md` and `implement-hook.md`
- Files: `fx-to-dotnet/commands/hooks/plan-hook.md`, `fx-to-dotnet/commands/hooks/implement-hook.md`
- `plan-hook.md`: update frontmatter description, contract block, step 2 (assess invocation note), the required-policies map row for `assess`, the `spec.md` annotation `Source:` line and "See …" reference, and the precondition gate enumeration.
- `implement-hook.md`: update precondition `2.a` and the user-facing remediation message to reference `.specify/migration/analysis.md`.
- **Done when**: same grep criterion as T029 satisfied for both files; coordinate with T025 (Layer 7 verification step) so the embedded canonical map already uses the new path.

### T032 [P] Repath `analysis.md` references in `fx-to-dotnet/README.md` and `docs/`
- Files: `fx-to-dotnet/README.md`, `docs/speckit-tight-integration-plan.md` (already updated as part of this change), `docs/speckit-tight-integration-tasks.md` (this file).
- Update README hook-table row for `after_plan`, gating-files list, and `plan` "Reads:" line.
- **Done when**: same grep criterion as T029 satisfied across `fx-to-dotnet/README.md` and `docs/`.

### T033 Workspace-wide path-cleanup audit
- Workspace grep (regex) for `\.fx-to-dotnet[/\\]analysis` MUST return zero matches.
- Workspace grep for `\.specify/migration/analysis\.md` MUST appear in producer (`assess.md`), consumers (`plan-hook.md`, `implement-hook.md`, `orchestrate.md`), and docs.
- Update `scripts/cross-reference-audit.{ps1,py}` if it hard-codes the old path; confirm both variants exit 0.
- Inspect `fx-to-dotnet/**` and every `commands/workflows/**/workflow.yml` for stray references; clean up if found.
- **Done when**: both greps satisfy the criteria; both audit scripts exit 0.

### T034 End-to-end relocation verification
- On a sandbox Framework solution, run `/speckit.plan`. Confirm `.specify/migration/analysis.md` is created and `.fx-to-dotnet/analysis.md` is **not** created.
- Confirm `after_plan` hook's policy-citation step (T025) successfully reads the new path.
- Confirm `/speckit.analyze` (core Spec Kit) can locate the file by convention without extension-specific knowledge.
- Negative: on a non-Framework solution, confirm no `.specify/migration/` directory is created by these hooks (silent-exit guard still works).
- **Done when**: all four bullets observed. Depends on T028–T033.

### T022 Security test (dispatch validator)
- Hand-edit a `[MIG]` task to `dispatch: speckit.evil.cmd(...)`.
- Run `/speckit.implement`.
- Confirm `implement-hook` rejects with a clear error and does not invoke the target.
- **Done when**: rejection observed and audit log captures the attempt.

---

## Dependency Graph

```
T001 ──► T002 [P] ─┐
        T003 [P] ─┤
        T004 [P] ─┼──► T008 ──► T009 [P]
        T005 [P] ─┤            T010 [P]
        T006 [P] ─┘            T011 [P]
        T007 [P] ──────────────T012 [P]
                                │
                                ├──► T013
                                ├──► T014 [P]
                                └──► T015 [P]
                                          │
                                          ▼
                            T016 ──► T017 ──► T018 ──► T019 ──► T020 ──► T021 ──► T022

Layer 7 (policy-loading enforcement):
        T022 [P] ─┐
        T023 [P] ─┼─► T025 ──► T026
        T024 [P] ─┘

Layer 8 (shared analysis artifact relocation):
        T027 ──► T028 ──► T029 [P] ─┐
                          T030 [P] ─┼─► T033 ──► T034
                          T031 [P] ─┤
                          T032 [P] ─┘
```

---

## Parallel Execution Examples

- **Wave 1** (after T001): launch T002, T003, T004, T005, T006, T007 in parallel.
- **Wave 2** (after T008): launch T009, T010, T011, T012 in parallel; T013, T014, T015 may also run in parallel with the preset work.
- **Wave 3** (verification): T016 first; once green, T017 → T022 sequentially (each depends on the previous side effects on the test solution).
- **Wave 4** (Layer 7): launch T022, T023, T024 in parallel; T025 after T022+T023; T026 after T024+T025.
- **Wave 5** (Layer 8): T027 first; then T028; then T029, T030, T031, T032 in parallel; T033 after all repath tasks; T034 last.

---

## Acceptance Summary

All prior tasks plus the Layer 7 (T022–T026) and Layer 8 (T027–T034) phases complete and verification phase green ⇒ the six contractual goals from the plan are met **and** `analysis.md` is a Spec-Kit-discoverable shared artifact:

1. Plan content owned by extension (T003, T010, T012).
2. Additive marked sections in `spec.md` / `plan.md` / `tasks.md` (T002–T004, T006).
3. Assessment + plan **must** complete before implement (T003, T004, T005, T008 mandatory hooks, T018).
4. Migrations execute first (T004 insertion before user stories; T005 ordering).
5. Implement only invokes `speckit.fx-to-dotnet.*` (T005 dispatch validator, T011 preset directive, T022 security test).
6. Each migration change reviewed by user (T005 per-task review loop, T007 inner gates).
7. **Policies demonstrably applied** — every required policy is loaded and cited in the output artifacts; missing citations block `speckit.plan` (T022–T026).
8. **`analysis.md` is shared** — located at `.specify/migration/analysis.md`, registered in `extension.yml`, and discoverable by core Spec Kit commands (T027–T034).

> Note: a duplicate `T022` ID exists (Layer 7 policy-hardening *and* the security-test row). Treat the security test as `T022-sec` until a renumber pass; the dependency graph above disambiguates by phase.
