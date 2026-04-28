# FxToNet Spec-Kit Workflow Plan

## Summary

Create 8 scenario-based workflow commands and enhance 8 existing phase commands with spec-kit `handoffs:` to provide multiple migration entry points — from assessment-only to targeted migration scenarios. Register all in `extension.yml`. The 5 existing SDD bridge commands remain available as standalone extension commands (not hooks).

### Problem

The extension currently has 16 commands (8 core phases + 5 SDD bridge commands + 3 utilities) but no `handoffs:` property on any of them. Workflow chaining is implicit via `invoke-command`. The only composite entry point is the monolithic `orchestrate` command which runs the entire 7-phase migration sequentially. There are no purpose-built entry points for common scenarios like "just assess my solution", "migrate only libraries", or "modernize project files without changing TFM".

### Solution

Introduce 8 composite workflow commands that chain existing phase commands using spec-kit's `handoffs:` mechanism. The recommended path is `assess-and-plan` → `sdk-normalize` → `package-modernize` → `package-update` → `library-plan` → then `web-app-migration` for web projects. A single `migrate-all` orchestration workflow runs the full sequence end-to-end. Add `handoffs:` to all 8 phase/utility commands so they form a navigable graph. The 5 existing SDD bridge commands (`specify-hook`, `plan-hook`, `tasks-hook`, `implement-hook`, `verify-hook`) remain registered as extension commands and can be invoked directly via `invoke-command` — they are not registered as hooks.

---

## Architecture

### Workflow Graph

```
  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                              migrate-all                                                                                      │
  │  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌────────────────┐ │
  │  │ assess-and-plan │───→│ sdk-normalize    │───→│ package-        │───→│ package-update  │───→│ library-plan    │───→│ library-update  │───→│ web-app-       │ │
  │  │ (detect→assess  │    │ (detect→convert  │    │ modernize       │    │ (update-pkgs    │    │ (document libs  │    │ (multitarget    │    │ migration      │ │
  │  │  →plan)         │    │  →fix)           │    │ (assess→plan)   │    │  →fix per chunk)│    │  →iterate)      │    │  single lib)    │    │ (multitarget→  │ │
  │  └─────────────────┘    └──────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘    │  inventory→    │ │
  │                                                                                                                                            │  web-migrate→  │ │
  │                                                                                                                                            │  verify)       │ │
  │                                                                                                                                            └────────────────┘ │
  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

The `migrate-all` workflow runs the full sequence end-to-end: `assess-and-plan` → `sdk-normalize` → `package-modernize` → `package-update` → `library-plan` → `web-app-migration`. Each step builds on the previous: assessment produces the plan, SDK normalization converts project files, package modernization audits and plans NuGet updates, package update executes those updates, library plan documents all non-web projects and orchestrates `library-update` for each one, then web-app-migration handles web host migration. Each sub-workflow can also be invoked independently for targeted scenarios.

### Phase Command Handoff Chain

```
detect ──→ assess ──→ plan ──→ convert ──→ update-packages ──→ multitarget ──→ web-migrate ──→ verify
                                  │              │                  │               │
                                  └→ fix         └→ fix            └→ fix          └→ fix
```

### SDD Bridge Commands

The 5 existing SDD bridge commands remain registered as extension commands (not hooks). They can be invoked directly or from workflows via `invoke-command`:

```
speckit.fx-to-dotnet.specify-hook   ← early detection (called from assess-and-plan or standalone)
speckit.fx-to-dotnet.plan-hook      ← assessment + planning (called from assess-and-plan or standalone)
speckit.fx-to-dotnet.tasks-hook     ← generate [MIG] tasks (standalone)
speckit.fx-to-dotnet.implement-hook ← execute [MIG] tasks (standalone)
speckit.fx-to-dotnet.verify-hook    ← build + completion report (called from web-app-migration or standalone)
```

No `hooks:` section in `extension.yml` — all invocations are explicit via commands or workflows.

### Review Point Policy

Every workflow step that **mutates code** (converts projects, updates packages, multitargets, migrates web code) is followed by a **review point** — a pause where the agent reports what changed and waits for user approval before continuing.

**Review point behavior:**
- **Default (interactive):** Pause after each mutation step. Report: files changed, build status, issues found. Offer: approve & continue / reject & rollback / stop.
- **Override (automation):** Set `autoApprove: true` in `.fx-to-dotnet/preferences.md` to skip all review points and continue automatically. Workflows also accept an `autoApprove` parameter to override per-run without modifying the preferences file.
- **Granularity:** Review points occur at the natural checkpoint level for each workflow — per-layer, per-chunk, per-library, or per-phase depending on the workflow.

**Review point logic (pseudocode):**
```
after mutation step:
  record result in state file
  if build failed → always pause (even with autoApprove)
  if autoApprove and build passed → log review summary, continue
  else → present review summary, wait for user approval
```

**Override precedence:** per-run parameter > `.fx-to-dotnet/preferences.md` > default (pause).

Read-only workflows (`assess-and-plan`, `package-modernize`) have no review points since they produce analysis/plans without code changes.

---

## Phase 1: New Workflow Commands

8 new files in `fx-to-dotnet/commands/workflows/{name}/workflow.yaml`.

### 1. migrate-all

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.migrate-all` |
| **File** | `commands/workflows/migrate-all/workflow.yaml` |
| **Purpose** | Run the full migration sequence end-to-end — from assessment through web app migration |
| **Flow** | assess-and-plan → sdk-normalize → package-modernize → package-update → library-plan → web-app-migration |
| **Outputs** | All `.fx-to-dotnet/` state files produced by each sub-workflow |
| **Use case** | "Migrate my entire solution from .NET Framework to modern .NET" |
| **Handoffs** | (none — this is the top-level entry point) |

**Workflow steps:**
1. Resolve solution path and target framework (default: net10.0)
2. Invoke `speckit.fx-to-dotnet.assess-and-plan` — detect, assess, and plan the migration
3. **Phase checkpoint:** present plan summary; wait for approval before making code changes
4. Invoke `speckit.fx-to-dotnet.sdk-normalize` — convert legacy projects to SDK-style (layer-by-layer with review points)
5. **Phase checkpoint:** report SDK normalization results
6. Invoke `speckit.fx-to-dotnet.package-modernize` — audit package compatibility and generate chunked plan
7. **Phase checkpoint:** present package update plan summary
8. Invoke `speckit.fx-to-dotnet.package-update` — execute chunked package updates (with review points per chunk)
9. **Phase checkpoint:** report package update results
10. Invoke `speckit.fx-to-dotnet.library-plan` — plan and migrate all non-web libraries (with review points per library/layer)
11. **Phase checkpoint:** report library migration results
12. If web-app-host projects exist: invoke `speckit.fx-to-dotnet.web-app-migration` — multitarget, inventory, web-migrate, verify
13. Present final migration summary with completion report

### 2. assess-and-plan

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.assess-and-plan` |
| **File** | `commands/workflows/assess-and-plan/workflow.yaml` |
| **Purpose** | Evaluate migration scope and effort — assessment and planning only, no code changes |
| **Flow** | detect → assess → plan |
| **Outputs** | `.fx-to-dotnet/detection.md`, `.fx-to-dotnet/analysis.md`, `.fx-to-dotnet/package-updates.md`, `.fx-to-dotnet/plan.md` |
| **Use case** | "What does migration look like for my solution?" |
| **Handoffs** | → `sdk-normalize` |

**Workflow steps:**
1. Resolve solution path from user input or workspace search
2. Run `speckit.fx-to-dotnet.detect` on each project to classify the solution
3. Run `speckit.fx-to-dotnet.assess` to gather frameworks, dependencies, blockers, and package compatibility
4. Run `speckit.fx-to-dotnet.plan` to synthesize findings into a layered migration plan with chunked package updates
5. Present summary: project count, classifications, layer count, estimated phases, risks
6. Offer handoff to `sdk-normalize` (recommended next step)

### 3. sdk-normalize

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.sdk-normalize` |
| **File** | `commands/workflows/sdk-normalize/workflow.yaml` |
| **Purpose** | Convert all legacy project files to SDK-style format without changing target framework |
| **Flow** | detect → convert (layer-by-layer) → fix |
| **Prerequisite** | `assess-and-plan` recommended (`.fx-to-dotnet/plan.md` provides layer ordering) but not required |
| **Outputs** | `.fx-to-dotnet/{ProjectName}.md` (per-project conversion state) |
| **Use case** | "Convert projects to SDK-style project files" |
| **Handoffs** | → `package-modernize` |

**Workflow steps:**
1. Resolve solution path
2. Run `speckit.fx-to-dotnet.detect` on each project to identify which need conversion
3. If `.fx-to-dotnet/plan.md` exists, use its dependency layer ordering; otherwise compute layers from detect results
4. For each dependency layer (leaf-first):
   - Invoke `speckit.fx-to-dotnet.convert` for projects that are not already SDK-style
   - Invoke `speckit.fx-to-dotnet.fix` to validate build after each layer
   - **Review point:** report converted projects, build status, files changed; wait for approval (skipped if `autoApprove` and build passed)
5. Summary: report converted vs already-SDK-style vs skipped projects
6. Offer handoff to `package-modernize` (recommended next step)

### 4. package-modernize

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.package-modernize` |
| **File** | `commands/workflows/package-modernize/workflow.yaml` |
| **Purpose** | Audit NuGet package compatibility and generate a chunked update plan — no code changes |
| **Flow** | assess (package audit) → plan (package chunks) |
| **Prerequisite** | `sdk-normalize` completed (projects must be SDK-style) |
| **Outputs** | `.fx-to-dotnet/analysis.md` (updated), `.fx-to-dotnet/package-updates.md` (chunked plan) |
| **Use case** | "What packages need updating and in what order?" |
| **Handoffs** | → `package-update` |

**Workflow steps:**
1. Resolve solution path
2. Pre-check: verify all projects are SDK-style; if not, suggest `sdk-normalize` first
3. Run `speckit.fx-to-dotnet.assess` (package compatibility subset — audit NuGet feeds, identify incompatible/outdated packages)
4. Run `speckit.fx-to-dotnet.plan` (generate chunked package update plan — minor before major, grouped by risk)
5. Present summary: package count, chunks, risk levels, unsupported libraries and their resolutions
6. Offer handoff to `package-update` (recommended next step)

### 5. package-update

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.package-update` |
| **File** | `commands/workflows/package-update/workflow.yaml` |
| **Purpose** | Execute 1–N package update chunks from the package modernization plan |
| **Flow** | update-packages (per chunk) → fix (per chunk) |
| **Prerequisite** | `package-modernize` completed (`.fx-to-dotnet/package-updates.md` has chunked plan) |
| **Outputs** | Updated `.csproj` files, `.fx-to-dotnet/package-updates.md` (chunk results) |
| **Use case** | "Apply the planned package updates" |
| **Handoffs** | → `library-plan` |

**Workflow steps:**
1. Resolve solution path
2. Pre-check: verify `.fx-to-dotnet/package-updates.md` exists with chunked plan; if not, suggest `package-modernize` first
3. Resume check: if some chunks already completed, resume from first incomplete chunk
4. For each chunk (minor updates before major):
   - Invoke `speckit.fx-to-dotnet.update-packages` with chunk data
   - Invoke `speckit.fx-to-dotnet.fix` to validate build
   - Record chunk result in `.fx-to-dotnet/package-updates.md`
   - **Review point:** report updated packages, build status, changed `.csproj` files; wait for approval (skipped if `autoApprove` and build passed)
5. Summary: report total updated packages, remaining incompatibilities, build status
6. Offer handoff to `library-plan` (recommended next step)

### 6. library-plan

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.library-plan` |
| **File** | `commands/workflows/library-plan/workflow.yaml` |
| **Purpose** | Document all non-web library projects, plan migration order, and orchestrate `library-update` for each |
| **Flow** | enumerate libraries from plan → document each → for each library: invoke `library-update` |
| **Prerequisite** | `package-update` completed |
| **Scope filter** | `class-library`, `console-app`, `windows-service`, `web-library` (excludes `web-app-host`) |
| **Outputs** | `.fx-to-dotnet/library-plan.md` (library inventory with migration order and per-library status) |
| **Use case** | "Plan and migrate all non-web library projects" |
| **Handoffs** | → `web-app-migration` |

**Workflow steps:**
1. Resolve solution path + target framework (default: net10.0)
2. Pre-check: verify `.fx-to-dotnet/plan.md` exists and package updates are complete; if not, suggest prior workflows
3. Load project list from `.fx-to-dotnet/plan.md`; filter to non-web classifications (`class-library`, `console-app`, `windows-service`, `web-library`)
4. Compute dependency layers (leaf-first order) and document in `.fx-to-dotnet/library-plan.md`:
   - Per library: project name, classification, dependency layer, dependencies, migration status
   - Migration order: leaf-first within each layer
5. Resume check: if some libraries already completed, resume from first incomplete library
6. For each dependency layer (leaf-first), for each library in that layer:
   - Invoke `speckit.fx-to-dotnet.library-update` for the library
   - Record result in `.fx-to-dotnet/library-plan.md`
   - **Review point (per-library):** report migration status, build result, files changed; wait for approval (skipped if `autoApprove` and build passed)
   - **Review point (per-layer):** after all libraries in layer complete, report layer summary; wait for approval (skipped if `autoApprove` and all builds passed)
7. Summary: report migrated vs skipped vs remaining libraries, build status
8. Offer handoff to `web-app-migration` if web-app-host projects exist

### 7. library-update

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.library-update` |
| **File** | `commands/workflows/library-update/workflow.yaml` |
| **Purpose** | Multitarget a single library project to modern .NET |
| **Flow** | multitarget-migrate → fix |
| **Prerequisite** | Called from `library-plan` (or standalone with project path) |
| **Outputs** | `.fx-to-dotnet/{ProjectName}.md` (per-project multitarget state) |
| **Use case** | "Multitarget one library project to modern .NET" |
| **Handoffs** | (returns to `library-plan` caller) |

**Workflow steps:**
1. Resolve project path and target framework from caller or user input
2. Pre-check: verify project is SDK-style and packages are updated; if not, suggest prior workflows
3. Invoke `speckit.fx-to-dotnet.multitarget-migrate` for the project
4. Invoke `speckit.fx-to-dotnet.fix` to validate build
5. Record result in `.fx-to-dotnet/{ProjectName}.md`
6. **Review point:** report project migration status, build result, files changed; wait for approval (skipped if `autoApprove` and build passed, or if called from `library-plan` which manages its own review points)

### 8. web-app-migration

| Field | Value |
|-------|-------|
| **Command** | `speckit.fx-to-dotnet.web-app-migration` |
| **File** | `commands/workflows/web-app-migration/workflow.yaml` |
| **Purpose** | Full migration with web application emphasis — includes route inventory |
| **Flow** | multitarget → inventory → web-migrate → verify |
| **Prerequisite** | `library-plan` completed (non-web projects multitargeted) |
| **Use case** | "Migrate an ASP.NET Framework web application" |

**Workflow steps:**
1. Pre-check: verify `.fx-to-dotnet/plan.md` exists and library plan is complete; if not, suggest prior workflows
2. Multitarget Migration: invoke `speckit.fx-to-dotnet.multitarget-migrate` per layer → **review point (per-layer):** report multitargeted projects, build status; wait for approval (skipped if `autoApprove` and build passed)
3. Route Inventory: invoke `speckit.fx-to-dotnet.inventory` on web-app-host projects to map endpoints, controllers, filters, auth requirements
4. **Review point:** report inventory results — endpoint count, controllers, auth requirements; wait for approval before proceeding to code migration (skipped if `autoApprove`)
5. Web Migration: invoke `speckit.fx-to-dotnet.web-migrate` with inventory data → slice-based porting
6. **Review point:** report migrated slices, build status, files changed; wait for approval (skipped if `autoApprove` and build passed)
7. Verification: invoke `speckit.fx-to-dotnet.verify-hook` → completion report

---

## Phase 2: Enhance Existing Commands with Handoffs

Add `handoffs:` YAML frontmatter to 8 existing phase/utility commands.

### Handoff Definitions

| # | Command | Handoffs | send |
|---|---------|----------|------|
| 1 | `assess` | → "Generate Migration Plan" (`speckit.fx-to-dotnet.plan`) | `true` |
| | | → "Review Assessment" (user reviews `.fx-to-dotnet/analysis.md`) | `false` |
| 2 | `plan` | → "Normalize to SDK-Style" (`speckit.fx-to-dotnet.sdk-normalize`) | `false` |
| | | → "Start SDK Conversion" (`speckit.fx-to-dotnet.convert`) | `false` |
| 3 | `convert` | → "Modernize Packages" (`speckit.fx-to-dotnet.package-modernize`) | `false` |
| | | → "Convert Next Project" (`speckit.fx-to-dotnet.convert`) | `false` |
| 4 | `update-packages` | → "Update Next Chunk" (`speckit.fx-to-dotnet.update-packages`) | `false` |
| | | → "Start Multitarget Migration" (`speckit.fx-to-dotnet.multitarget-migrate`) | `false` |
| 5 | `multitarget-migrate` | → "Start Web Migration" (`speckit.fx-to-dotnet.web-migrate`) | `false` |
| | | → "Verify Migration" (`speckit.fx-to-dotnet.verify-hook`) | `false` |
| 6 | `web-migrate` | → "Verify Migration" (`speckit.fx-to-dotnet.verify-hook`) | `true` |
| 7 | `detect` | → "Run Full Assessment" (`speckit.fx-to-dotnet.assess`) | `false` |
| 8 | `inventory` | → "Start Web Migration" (`speckit.fx-to-dotnet.web-migrate`) | `false` |

### Handoff YAML Format

```yaml
handoffs:
  - label: "Generate Migration Plan"
    agent: speckit.fx-to-dotnet.plan
    prompt: "Generate a migration plan from the assessment in .fx-to-dotnet/analysis.md"
    send: true
  - label: "Review Assessment"
    agent: speckit.fx-to-dotnet.assess
    prompt: "Review the assessment output in .fx-to-dotnet/analysis.md"
    send: false
```

### Send Policy

- `send: true` — Auto-invoke on completion. Used for natural continuations where the next step is always expected (assess→plan, web-migrate→verify).
- `send: false` — User clicks to proceed. Used for all other transitions to maintain checkpoint control and allow review between phases.

---

## Phase 3: Register in extension.yml

### New Commands to Register

```yaml
provides:
  commands:
    # --- Workflow commands ---
    - name: "speckit.fx-to-dotnet.migrate-all"
      file: "commands/workflows/migrate-all/workflow.yaml"
    - name: "speckit.fx-to-dotnet.assess-and-plan"
      file: "commands/workflows/assess-and-plan/workflow.yaml"
    - name: "speckit.fx-to-dotnet.sdk-normalize"
      file: "commands/workflows/sdk-normalize/workflow.yaml"
    - name: "speckit.fx-to-dotnet.package-modernize"
      file: "commands/workflows/package-modernize/workflow.yaml"
    - name: "speckit.fx-to-dotnet.package-update"
      file: "commands/workflows/package-update/workflow.yaml"
    - name: "speckit.fx-to-dotnet.library-plan"
      file: "commands/workflows/library-plan/workflow.yaml"
    - name: "speckit.fx-to-dotnet.library-update"
      file: "commands/workflows/library-update/workflow.yaml"
    - name: "speckit.fx-to-dotnet.web-app-migration"
      file: "commands/workflows/web-app-migration/workflow.yaml"
```

No `hooks:` section — the 5 SDD bridge commands are already registered as extension commands in the existing `provides.commands` block.

### Final Command Count

| Category | Count | Commands |
|----------|-------|----------|
| Core migration | 8 | orchestrate, assess, plan, convert, fix, update-packages, multitarget-migrate, web-migrate |
| Utilities | 3 | detect, inventory, show-policy |
| SDD bridge commands | 5 | specify-hook, plan-hook, tasks-hook, implement-hook, verify-hook |
| **Workflows** | **8** | **migrate-all, assess-and-plan, sdk-normalize, package-modernize, package-update, library-plan, library-update, web-app-migration** |
| **Total** | **24** | |

---

## State Management

All workflows share the `.fx-to-dotnet/` state directory. Running `assess-and-plan` then `library-plan` works because each phase command has resume logic built in.

```
{solutionDir}/.fx-to-dotnet/
├── detection.md          ← detect, assess-and-plan, sdk-normalize
├── analysis.md           ← assess (all workflows)
├── package-updates.md    ← assess (all workflows)
├── plan.md               ← plan (all workflows) + orchestrator state
├── library-plan.md       ← library-plan (library inventory + migration status)
├── preferences.md        ← user checkpoint preferences (`autoApprove`, `alwaysContinue`)
├── completion.md         ← verify-hook command, web-app-migration
└── {ProjectName}.md      ← per-project state (convert, multitarget, web-migrate)
```

---

## Decisions

| Decision | Rationale |
|----------|-----------|
| Flat command naming (`speckit.fx-to-dotnet.library-update`) | Consistent with spec-kit `speckit.{ext-id}.{command}` convention |
| Workflows in `commands/workflows/{name}/` | Separates composite workflows from atomic phase commands |
| `package-modernize` is assessment + planning only | Keeps package audit/planning read-only (no code changes); users review the chunked update plan before committing to package updates |
| `package-update` is a separate execution workflow | Package updates modify project files and can break builds; separating execution from planning gives a clear checkpoint and allows partial execution (1–N chunks) |
| `orchestrate` retained as-is | Monolithic orchestrator still useful for standalone (non-spec-kit) usage; `migrate-all` is the workflow-based equivalent that delegates to sub-workflows with review points between phases |
| `send: false` default for inter-phase handoffs | Preserves user checkpoint control; `send: true` only for natural continuations |
| Review points after every mutation step | Ensures user can inspect changes before continuing; `autoApprove` override enables CI/automation without removing safety |
| Build failures always pause (even with `autoApprove`) | Prevents cascading failures in automated runs; broken builds require human decision |
| Extension commands instead of hooks | SDD bridge commands registered as `provides.commands` only; no `hooks:` section. Invocations are explicit via workflows or direct `invoke-command`, giving full control over when/if they run |
| No new scripts | Workflows reuse existing commands via `invoke-command`; build scripts already exist |

---

## Verification Checklist

- [ ] YAML validity: parse each file's frontmatter to confirm valid YAML
- [ ] Command naming: all follow `speckit.fx-to-dotnet.{name}` pattern
- [ ] Extension.yml: all 24 commands registered with correct file paths
- [ ] Handoff chain: trace each workflow end-to-end; no broken references
- [ ] Cross-reference audit: run `scripts/cross-reference-audit.ps1` / `.py`
- [ ] SDD bridge commands: all 5 registered as extension commands, no `hooks:` section present
- [ ] State file consistency: all workflows write to `.fx-to-dotnet/` with compatible format
- [ ] Review points: every mutation step followed by review point; `autoApprove` override tested
- [ ] Resume logic: each workflow resumes correctly from partial state
