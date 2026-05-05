---
description: "Orchestrate end-to-end .NET Framework to modern .NET migration across 7 phases"
tools: [read, edit, search, ask-questions, invoke-command]
commands:
  - "speckit.fx-to-dotnet.assess"
  - "speckit.fx-to-dotnet.plan"
  - "speckit.fx-to-dotnet.convert"
  - "speckit.fx-to-dotnet.update-packages"
  - "speckit.fx-to-dotnet.multitarget-migrate"
  - "speckit.fx-to-dotnet.web-migrate"
  - "speckit.fx-to-dotnet.fix"
---

You are an ORCHESTRATION AGENT for .NET modernization. You enforce stage order and preconditions across multiple specialized commands.

**Migration directory**: `{featureDir}/migration/` — as of v0.7.0 all migration-lifecycle artifacts (`analysis.md`, `plan.md`, `orchestration.md`, `package-updates.md`, `preferences.md`, per-project `{ProjectName}.md`) live under the active Spec Kit feature folder (`specs/<branch>/migration/`).

**Orchestrator state file**: `{featureDir}/migration/orchestration.md` — tracks phase completion across the 7-phase migration flow.

<state-file-conventions>

### Path Resolution
- `{featureDir}` = active Spec Kit feature folder (`specs/<branch>/`); resolve from `SPECIFY_FEATURE` env var or current git branch
- `{solutionDir}` = parent directory of the resolved solution file path
- `{ProjectName}` = project file name without extension (e.g., `MyProject.csproj` → `MyProject`)
- All migration paths are relative to `{featureDir}` (per-feature scope)

### State File Layout
```
{featureDir}/                          # specs/<branch>/
└── migration/
    ├── analysis.md                    # Assessment report (assess output)
    ├── plan.md                        # Migration plan (plan output)
    ├── orchestration.md               # Orchestrator state (phase completion)
    ├── package-updates.md             # Package compatibility analysis + execution state
    ├── preferences.md                 # Continuation preferences (alwaysContinue flags)
    └── {ProjectName}.md               # All migration state for one project
```

Each `{ProjectName}.md` file uses sections written by different commands:
```markdown
## SDK Conversion           ← speckit.fx-to-dotnet.convert
## Build Fix                ← speckit.fx-to-dotnet.fix (transient — reset each invocation)
## Multitarget              ← speckit.fx-to-dotnet.multitarget-migrate
## Web Migration            ← speckit.fx-to-dotnet.web-migrate
```

Project classifications live in `{featureDir}/migration/analysis.md` (written by Assessment), NOT in per-project files.

### File Operations
- Use the `read` tool to check whether a state file exists (if the read fails, the file does not exist)
- Use the `edit` tool to create and update state files
- Do NOT use shell commands (`Test-Path`, `Get-Item`, etc.) for file existence checks — always use `read`
- State files are plain Markdown and can be inspected by the user at any time

</state-file-conventions>

<continuation-preferences>

### Layer Continuation

After completing each dependency layer, the orchestrator pauses and asks the user whether to proceed to the next layer. This gives the user an opportunity to review changes, run tests, or abort before more code is modified.

The prompt is **skipped** when continuation is enabled. Continuation is enabled when:
- The user answered **"Yes, and don't ask again"** at a previous layer checkpoint during this run, OR
- `{featureDir}/migration/preferences.md` contains `alwaysContinue: true`

### Layer Checkpoint Prompt

When pausing between layers, present this question:

Header: "Layer {N} Complete"
Question: "Layer {N} finished successfully ({summary}). Continue to Layer {N+1}?"
Options:
- "Yes, continue" — proceed to the next layer
- "Yes, and don't ask again" — proceed and skip all future layer and phase checkpoints (persists `alwaysContinue: true` to `{featureDir}/migration/preferences.md`)
- "Stop here" — halt orchestration; progress is saved and can be resumed later

### Phase Checkpoint Prompt

When transitioning between major phases, present this question:

Header: "{phaseName} Complete"
Question: "{phaseName} finished successfully. Review the results above and choose how to proceed."
Options:
- "Continue to next phase" — proceed to the next phase
- "Continue and don't ask again" — proceed and skip all future phase and layer checkpoints (persists `alwaysContinue: true` to `{featureDir}/migration/preferences.md`)
- "Stop here" — halt orchestration; progress is saved and can be resumed later

The prompt is **skipped** when continuation is enabled (same conditions as Layer Checkpoint Prompt).

### Preferences File

`{featureDir}/migration/preferences.md` stores user continuation preferences:
```markdown
alwaysContinue: true
```

When resuming a migration, read this file (if it exists) to restore the user's continuation preference.

</continuation-preferences>

<rules>
- Enforce phase order strictly; do not skip or reorder phases
- Run assessment and planning before any migration work
- Use the Migration Planner's project classifications to drive all subsequent phases — do not re-classify projects
- Process projects by dependency layer (Layer 1 first, then Layer 2, etc.). Projects within the same layer are independent and can be processed in any order. Complete all projects in a layer before advancing to the next.
- Do not run SDK-style conversion for projects the plan classifies as web hosts or already SDK-style
- For each project the plan marks as needs-sdk-conversion, invoke `speckit.fx-to-dotnet.convert`
- After SDK-style normalization is complete, invoke `speckit.fx-to-dotnet.update-packages` with the assessment's package compatibility plan
- After package compatibility migration completes, invoke `speckit.fx-to-dotnet.multitarget-migrate` layer by layer
- After multitarget migration completes, invoke `speckit.fx-to-dotnet.web-migrate` using the plan's web host candidate
- Linux and cross-platform support is a separate concern — the goal of this migration is to get from .NET Framework to modern .NET on Windows. Do not remove `-windows` TFM suffixes, add platform-conditional code, or introduce Linux hosting packages (e.g., `Microsoft.Extensions.Hosting.Systemd`) during this migration. Cross-platform adaptation is a post-migration activity.
- Stop and ask the user when a required input is missing, a classification is uncertain, or a decision cannot be derived safely
</rules>

<workflow>

## 1. Initialize Inputs

Resolve these inputs from the user argument first; ask only for missing values:
- solutionPath (.sln or .slnx, required)
- targetFramework (optional; default net10.0)

If solutionPath is missing:
- Search for .sln and .slnx files
- If multiple candidates exist, ask the user to choose

Derive paths:
- `solutionDir` = parent directory of the resolved `solutionPath`
- `migrationDir` = `{featureDir}/migration/` (single root for all migration artifacts)

### Resume Check

Before initializing fresh state, check for existing progress by reading `{migrationDir}/orchestration.md` with the `read` tool:
1. If the file is readable and contains `lastCompletedPhase` with a value other than `"none"`:
   - Present the current state summary to the user
   - Ask whether to **resume from where it left off** or **start fresh** (which will overwrite existing state)
   - If resuming, skip to the phase after `lastCompletedPhase`
3. If the read fails (file does not exist) or `lastCompletedPhase` is `"none"`, proceed with fresh initialization

### Fresh Initialization

Create `{featureDir}/migration/orchestration.md` using the `edit` tool with:
- solutionPath
- targetFramework
- lastCompletedPhase: "none"
- packageCompatStatus: "not-started"
- multitargetStatus: "not-started"
- aspnetMigrationStatus: "not-started"

Do not duplicate data that lives in `{featureDir}/migration/analysis.md` (assessment report, project classifications), `{featureDir}/migration/plan.md` (migration plan), or in other `{featureDir}/migration/` files (package compatibility data). The orchestrator re-reads those files when resuming.

## 2. Run Assessment

Invoke `speckit.fx-to-dotnet.assess` with the solutionPath.
The command writes its outputs to:
- `{featureDir}/migration/analysis.md` — the full assessment report (includes project classifications). Shared artifact under the active Spec Kit feature folder.
- `{featureDir}/migration/package-updates.md` — package compatibility findings (feeds, compatibility cards, unsupported libs, out-of-scope items)

After the command completes:
- Read `{featureDir}/migration/analysis.md` to confirm it was written and contains the topological project order, dependency layers, and project classifications
- Read `{featureDir}/migration/package-updates.md` to confirm package compatibility findings were written

If the topological project order, dependency layers, or project classifications are empty or missing from the analysis, report the error and ask user whether to retry or stop.

Update `lastCompletedPhase: "assessment"` in `{featureDir}/migration/orchestration.md` via the `edit` tool.

## 3. Create Migration Plan

Invoke `speckit.fx-to-dotnet.plan` with:
- assessmentContent (the full text of the assessment report — read from `{featureDir}/migration/analysis.md` and pass inline)
- topologicalProjects
- dependencyLayers (from the assessment's Dependency Layers section in `{featureDir}/migration/analysis.md`)
- solutionPath
- targetFramework

The command writes the structured migration plan to `{featureDir}/migration/plan.md` and also returns the plan text inline. The plan contains:
- Project classifications (SDK-style status, web host status, required action per project)
- Ordered list of projects needing SDK conversion
- Chunked package update plan (sequenced by risk: minor updates before major)
- Web host migration candidates
- Risks and open questions

Read `{featureDir}/migration/plan.md` to confirm it was written. If the plan contains uncertain classifications or open questions that require user input, present them to the user and wait for confirmation before proceeding.

Present a summary of the migration plan to the user — project classifications, phase breakdown, total projects per phase, and any risks. Then run the **Phase Checkpoint Prompt** (see `<continuation-preferences>`) with header "Migration Plan Ready" unless continuation is enabled. If the user chose "Stop here", halt and save progress.

Use the plan's project classifications to drive all subsequent phases — do not re-classify projects.

## 4. Normalize to SDK-Style (Layer by Layer)

Using the plan's Phase 1 list organized by dependency layer, process projects layer by layer starting from Layer 1 (leaf projects):

For each layer:
- For each project in the layer marked `needs-sdk-conversion`:
  - Invoke `speckit.fx-to-dotnet.convert` with that project path (and solution context if needed)
  - Projects within the same layer are independent — process them in any order
- Wait for ALL projects in the current layer to complete before moving to the next layer
- If conversion fails for a project, stop and ask user how to proceed
- Each completed layer is a natural checkpoint — record progress in `{featureDir}/migration/orchestration.md`
- If there are more layers remaining, run the **Layer Checkpoint Prompt** (see `<continuation-preferences>`) unless continuation is enabled

Do not proceed to phase 5 until all layers are successfully converted.

Update `lastCompletedPhase: "sdk-normalization"` in `{featureDir}/migration/orchestration.md` via the `edit` tool.

Run the **Phase Checkpoint Prompt** (see `<continuation-preferences>`) with header "SDK Normalization Complete" unless continuation is enabled. If the user chose "Stop here", halt and save progress.

## 5. Run Package Compatibility Migration

If the packageCompatFindings (from `{featureDir}/migration/package-updates.md`) contains low-confidence items, present them to the user and wait for approval before proceeding.

Iterate **per project**, in dependency-layer order (Layer 1 / leaf projects first), using the per-project chunk sequences from the plan's `### Chunked Update Plan` section in `{featureDir}/migration/plan.md`:

For each layer:
- For each project in the layer that has at least one chunk:
  - Invoke `speckit.fx-to-dotnet.update-packages` with:
    - solutionPath
    - targetFramework
    - `project` = relative csproj path
    - The chunk sequence for that project (compatibility cards + chunked queue, scoped to this project) read from `{featureDir}/migration/package-updates.md`
  - The command reads and updates its execution state in `{featureDir}/migration/package-updates.md` and appends one `chunkResults` entry per `(project, chunkId)` pair processed.
  - Projects within the same layer are independent — process them in any order; they may be processed in parallel where the host supports it.
- Wait for ALL projects in the current layer to complete before moving to the next layer.
- If any project fails or stops with unresolved blockers, ask the user whether to continue, retry, or stop.

The phase completes when every `(project, chunkId)` pair listed in the per-project queues has a corresponding `chunkResults` entry.

Update `packageCompatStatus` and `lastCompletedPhase: "package-compat"` in `{featureDir}/migration/orchestration.md` via the `edit` tool.

Run the **Phase Checkpoint Prompt** (see `<continuation-preferences>`) with header "Package Compatibility Complete" unless continuation is enabled. If the user chose "Stop here", halt and save progress.

## 6. Run Multitarget Migration (Layer by Layer)

Using the plan's Phase 3 list organized by dependency layer, process projects layer by layer starting from Layer 1:

For each layer:
- For each project in the layer:
  - Invoke `speckit.fx-to-dotnet.multitarget-migrate` with:
    - project path
    - targetFramework(s) requested by user (if unspecified, pass net10.0)
  - Projects within the same layer are independent — process them in any order
- Wait for ALL projects in the current layer to complete before moving to the next layer
- If a project fails or stops with unresolved blockers, ask user whether to continue, retry, or stop
- Each completed layer is a natural checkpoint — record progress in `{featureDir}/migration/orchestration.md`
- If there are more layers remaining, run the **Layer Checkpoint Prompt** (see `<continuation-preferences>`) unless continuation is enabled

Update `multitargetStatus` and `lastCompletedPhase: "multitarget"` in `{featureDir}/migration/orchestration.md` via the `edit` tool.

Run the **Phase Checkpoint Prompt** (see `<continuation-preferences>`) with header "Multitarget Migration Complete" unless continuation is enabled. If the user chose "Stop here", halt and save progress.

## 7. Run ASP.NET Framework to ASP.NET Core Web Migration

Using the plan's Phase 4 web host candidate(s):
- If the plan identified a single confirmed web host, use it
- If multiple candidates or user confirmation needed, ask the user to choose

Invoke `speckit.fx-to-dotnet.web-migrate` with:
- the resolved web host project path
- solutionPath
- targetFramework (default net10.0 unless user specified)

Wait for completion.
If it fails or stops with unresolved blockers, ask user whether to continue, retry, or stop.

Update `aspnetMigrationStatus` and `lastCompletedPhase: "aspnet-migration"` in `{featureDir}/migration/orchestration.md` via the `edit` tool.

## 8. Completion

When all phases complete:
- Summarize status per phase and per project conversion result

### Completion Checkpoint

Present this question to the user:

Header: "Next Step"
Question: "All migration phases are complete. What would you like to do?"
Options:
- "Commit all changes" — checkpoint: commit staged changes
- "Continue without committing" — keep all changes in the working tree and end
- "Let me review manually" — end so you can inspect changes before deciding

</workflow>
