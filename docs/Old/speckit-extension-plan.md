# Plan: Spec Kit Extension for .NET Framework → Modern .NET Migration

## TL;DR

Build a **single GitHub Spec Kit extension** (`fx-to-dotnet`) that orchestrates migrating .NET Framework applications to modern .NET (e.g. .NET 10) through a 7-phase workflow. **Each fx2dotnet agent becomes a command within the single extension**, with commands organized in their own folders. Policy documents and build scripts are bundled in the extension. The extension relies on external MCP servers (no built-in server).

> **Note**: This plan was originally written for an 11-extension family. The project has since been consolidated into a single extension with 11 commands. References to separate extension folders and IDs below reflect the original plan and have been updated where possible to match the current single-extension structure.

**Source approach**: Copy the markdown instruction bodies from the existing fx2dotnet agent files (`agents/*.md`) and skill files (`skills/*/SKILL.md`) into the new extension command files, then adapt them to Spec Kit command format.

---

## Architecture Overview

### Extension ~~Family~~ (Single Extension)

A single extension (`fx-to-dotnet`) with 11 commands — each command corresponds to one fx2dotnet agent:

| Command name | Role | Source agent |
|---|---|---|
| `speckit.fx-to-dotnet.orchestrate` | Orchestrator — drives 7-phase flow | `agents/dotnet-fx-to-modern-dotnet.md` |
| `speckit.fx-to-dotnet.assess` | Phase 1: Assessment | `agents/assessment.agent.md` |
| `speckit.fx-to-dotnet.plan` | Phase 2: Migration planning | `agents/migration-planner.agent.md` |
| `speckit.fx-to-dotnet.convert` | Phase 3: SDK-style conversion | `agents/sdk-project-conversion.agent.md` |
| `speckit.fx-to-dotnet.fix` | Cross-cutting: build/fix loop | `agents/build-fix.agent.md` |
| `speckit.fx-to-dotnet.update-packages` | Phase 4: Package compatibility | `agents/package-compat-core.agent.md` |
| `speckit.fx-to-dotnet.multitarget-migrate` | Phase 5: Multitarget migration | `agents/multitarget.agent.md` |
| `speckit.fx-to-dotnet.web-migrate` | Phase 6: ASP.NET web migration | `agents/aspnet-framework-to-aspnetcore-web-migration.agent.md` |
| `speckit.fx-to-dotnet.detect` | Utility: project type detection | `agents/project-type-detector.agent.md` |
| `speckit.fx-to-dotnet.inventory` | Utility: legacy route extraction | `agents/legacy-web-route-inventory.agent.md` |
| `speckit.fx-to-dotnet.show-policy` | Shared policies viewer | `skills/*/SKILL.md` + `skills/systemweb-adapters/references/*` |

### Command Dependency Graph

```
orchestrate
├── assess
│   ├── detect
│   └── (policies)
├── plan
│   └── (policies)
├── convert
│   └── fix
│       └── (policies)
├── update-packages
│   └── fix
├── multitarget-migrate
│   ├── fix
│   └── (policies)
└── web-migrate
    ├── inventory
    ├── fix
    └── (policies)
```

### Repo Layout

All commands live under `fx-to-dotnet/` in a single extension:

```
fx2dotnet/                             # Monorepo root
├── README.md
├── LICENSE
│
├── fx-to-dotnet/                      # Single extension
│   ├── extension.yml                  # Declares all 11 commands
│   ├── README.md
│   ├── commands/
│   │   ├── orchestrate/orchestrate.md
│   │   ├── assess/assess.md
│   │   ├── plan/plan.md
│   │   ├── sdk-convert/convert.md
│   │   ├── build-fix/fix.md
│   │   ├── package-compat/update.md
│   │   ├── multitarget/migrate.md
│   │   ├── web-migrate/migrate.md
│   │   ├── detect-project/detect.md
│   │   ├── route-inventory/inventory.md
│   │   └── policies/show.md
│   ├── scripts/
│   │   ├── bash/dotnet-build.sh
│   │   └── powershell/dotnet-build.ps1
│   └── policies/
│       ├── ef6-retention.md
│       ├── mcp-setup.md
│       ├── owin-identity.md
│       ├── systemweb-adapters.md
│       └── windows-service.md
│
├── scripts/                           # Repo-level tooling
│   ├── deploy-extensions.ps1
│   ├── deploy-extensions.sh
│   ├── package-extensions.ps1
│   ├── package-extensions.sh
│   ├── remove-extensions.ps1
│   ├── remove-extensions.sh
│   ├── bump-version.ps1
│   ├── bump-version.sh
│   ├── version-check.py
│   ├── cross-reference-audit.py
│   └── generate-catalog.py
│
├── skills/                            # Shared skills (used by commands)
│   ├── dependency-layers/SKILL.md
│   ├── ef6-migration-policy/SKILL.md
│   ├── nuget-package-compat/...
│   ├── owin-identity/SKILL.md
│   ├── systemweb-adapters/...
│   └── windows-service-migration/SKILL.md
│
└── docs/                              # Planning documents
    └── *.md
```

---

## Steps

### Phase A: Monorepo Scaffold (foundation — blocks everything)

1. **Create monorepo root files**
   - `README.md` — family overview, 7-phase diagram (Mermaid), dependency graph, bulk install instructions (`specify extension add` for all 11), prerequisites (external MCP servers, .NET SDK)
   - `LICENSE` — MIT (shared across all extensions)

2. **Create shared `.extensionignore` template** — Exclude `tests/`, `.github/`, `*.pyc`, dev artifacts; copied into each extension directory

### Phase B: Extension Manifest (single `extension.yml`)

The single extension has one `extension.yml` declaring all 11 commands:

```yaml
schema_version: "1.0"
extension:
  id: "fx-to-dotnet"
  name: ".NET Framework to Modern .NET Migration"
  version: "0.1.2"
  description: "Orchestrate end-to-end .NET Framework to modern .NET migration across 7 phases"
  author: "Microsoft"
  repository: "https://github.com/AzureAD/fx-to-dotnet-extensions"
  license: "MIT"
requires:
  speckit_version: ">=0.1.0"
  tools:
    - "Microsoft.GitHubCopilot.Modernization.Mcp"
provides:
  commands:
    - name: "speckit.fx-to-dotnet.orchestrate"
      file: "commands/orchestrate/orchestrate.md"
    - name: "speckit.fx-to-dotnet.assess"
      file: "commands/assess/assess.md"
    - name: "speckit.fx-to-dotnet.plan"
      file: "commands/plan/plan.md"
    - name: "speckit.fx-to-dotnet.convert"
      file: "commands/sdk-convert/convert.md"
    - name: "speckit.fx-to-dotnet.fix"
      file: "commands/build-fix/fix.md"
      scripts:
        - "scripts/bash/dotnet-build.sh"
        - "scripts/powershell/dotnet-build.ps1"
    - name: "speckit.fx-to-dotnet.update-packages"
      file: "commands/package-compat/update.md"
    - name: "speckit.fx-to-dotnet.multitarget-migrate"
      file: "commands/multitarget/migrate.md"
    - name: "speckit.fx-to-dotnet.web-migrate"
      file: "commands/web-migrate/migrate.md"
    - name: "speckit.fx-to-dotnet.detect"
      file: "commands/detect-project/detect.md"
    - name: "speckit.fx-to-dotnet.inventory"
      file: "commands/route-inventory/inventory.md"
    - name: "speckit.fx-to-dotnet.show-policy"
      file: "commands/policies/show.md"
```

#### 3. `fx-to-dotnet/extension.yml` — Single Extension
   - `id: fx-to-dotnet`
   - `requires.tools`: `Microsoft.GitHubCopilot.Modernization.Mcp`
   - `provides.commands`: all 11 commands listed above
   - **README.md**: Describes 7-phase flow, lists all commands

### Phase C: Command Files — Copy & Adapt (11 commands — parallelizable after Phase B)

Each command is created by: (a) copying the markdown body from the corresponding fx2dotnet agent file, (b) replacing the agent YAML frontmatter with Spec Kit command frontmatter, and (c) applying the adaptation checklist.

**Copy source mapping** (fx2dotnet agent → command file within the single extension):

| fx2dotnet source file | Command folder | Command file |
|---|---|---|
| `agents/dotnet-fx-to-modern-dotnet.md` | `commands/orchestrate/` | `orchestrate.md` |
| `agents/assessment.agent.md` | `commands/assess/` | `assess.md` |
| `agents/migration-planner.agent.md` | `commands/plan/` | `plan.md` |
| `agents/sdk-project-conversion.agent.md` | `commands/sdk-convert/` | `convert.md` |
| `agents/build-fix.agent.md` | `commands/build-fix/` | `fix.md` |
| `agents/package-compat-core.agent.md` | `commands/package-compat/` | `update.md` |
| `agents/multitarget.agent.md` | `commands/multitarget/` | `migrate.md` |
| `agents/aspnet-framework-to-aspnetcore-web-migration.agent.md` | `commands/web-migrate/` | `migrate.md` |
| `agents/project-type-detector.agent.md` | `commands/detect-project/` | `detect.md` |
| `agents/legacy-web-route-inventory.agent.md` | `commands/route-inventory/` | `inventory.md` |

**Adaptation checklist** (apply to every copied file):

1. **Frontmatter**: Replace agent YAML (`name`, `description`, `argument-hint`, `tools`, `agents`, `handoffs`) with Spec Kit command YAML (`description`, `tools`, `scripts`)
2. **State directory**: Find-and-replace all `.fx2dotnet/` references → `.specify/migration/`
3. **Agent invocations → cross-extension command invocations**: Replace "invoke [AgentName] subagent" / "delegate to [AgentName]" with the target extension's command name:
   - "invoke Build Fix subagent" → "invoke `speckit.fx-to-dotnet.fix`"
   - "invoke Assessment subagent" → "invoke `speckit.fx-to-dotnet.assess`"
   - "invoke Migration Planner" → "invoke `speckit.fx-to-dotnet.plan`"
   - "invoke SDK-Style Conversion" → "invoke `speckit.fx-to-dotnet.convert`"
   - "invoke Package Compat Core" → "invoke `speckit.fx-to-dotnet.update-packages`"
   - "invoke Multitarget" → "invoke `speckit.fx-to-dotnet.multitarget-migrate`"
   - "invoke ASP.NET Web Migration" → "invoke `speckit.fx-to-dotnet.web-migrate`"
   - "invoke Project Type Detector" → "invoke `speckit.fx-to-dotnet.detect`"
   - "invoke Legacy Web Route Inventory" → "invoke `speckit.fx-to-dotnet.inventory`"
4. **Skill references → policy file references**: Replace "load/follow [skill-name] skill" with "reference `policies/<name>.md`":
   - "follow ef6-migration-policy skill" → "reference `policies/ef6-retention.md`"
   - "follow systemweb-adapters skill" → "reference `policies/systemweb-adapters.md`"
   - "follow windows-service-migration skill" → "reference `policies/windows-service.md`"
   - "follow owin-identity skill" → "reference `policies/owin-identity.md`"
5. **Handoffs**: Remove "Commit Changes" handoff references; replace with explicit "checkpoint: commit staged changes" instructions
6. **Terminal execution**: Replace "run via subagent" terminal instructions with "run via script" referencing `scripts/bash/dotnet-build.sh` or `scripts/powershell/dotnet-build.ps1`
7. **Explore agent**: Replace "delegate to Explore subagent" with direct file-read/search tool usage

**State convention** (shared across all extensions): All state persisted under `{solutionDir}/.specify/migration/`:
- `plan.md` — orchestrator state + migration plan
- `analysis.md` — assessment findings
- `package-updates.md` — package compatibility state
- `preferences.md` — user continuation preferences
- `{ProjectName}.md` — per-project state (sections for SDK Conversion, Build Fix, Multitarget, Web Migration)

#### 14. `fx-to-dotnet/commands/orchestrate/orchestrate.md` — *Orchestrator*
   - **Source**: `agents/dotnet-fx-to-modern-dotnet.md`
   - **description**: "Orchestrate end-to-end .NET Framework to modern .NET migration across 7 phases"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Input resolution: solution path (.sln/.slnx), target framework (default net10.0), state root derivation
     - Resume check: read `.specify/migration/plan.md`; ask user to resume or start fresh
     - Phase gate enforcement: invokes commands in order:
       1. `speckit.fx-to-dotnet.assess` → Assessment
       2. `speckit.fx-to-dotnet.plan` → Planning
       3. `speckit.fx-to-dotnet.convert` → SDK Conversion (layer-by-layer)
       4. `speckit.fx-to-dotnet.update-packages` → Package Compat
       5. `speckit.fx-to-dotnet.multitarget-migrate` → Multitarget (layer-by-layer)
       6. `speckit.fx-to-dotnet.web-migrate` → Web Migration
       7. Completion / Deferred Work
     - Dependency-layer processing: Layer 1 (leaf projects) first, Layer N depends on Layer N-1
     - Commit checkpoint after each phase/sub-step

#### 15. `fx-to-dotnet/commands/assess/assess.md` — *Phase 1: Assessment*
   - **Source**: `agents/assessment.agent.md`
   - **description**: "Gather solution info, identify frameworks, dependencies, blockers; classify projects; audit package compatibility"
   - **tools**: MCP tools (`get_state`, `get_scenarios`, `get_instructions`, `start_task`, `complete_task`, `get_projects_in_topological_order`), `dependency-layers` skill (inline computation), `nuget-package-compat` skill scripts (`findRecommendedUpgrades`), file read/write, search, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Resume check for existing `.specify/migration/analysis.md`
     - MCP initialization sequence
     - Topological ordering + dependency layer computation
     - Project classification: invoke `speckit.fx-to-dotnet.detect` per project
     - NuGet feed resolution + package discovery + compatibility cards
     - Out-of-scope identification: reference policy docs from `fx-to-dotnet` (policies)
     - Output: persist `analysis.md` and `package-updates.md`

#### 16. `fx-to-dotnet/commands/plan/plan.md` — *Phase 2: Planning*
   - **Source**: `agents/migration-planner.agent.md`
   - **description**: "Synthesize assessment findings into actionable, layered migration plan with chunked package updates"
   - **tools**: file read/write, search
   - **Body** (copied from source, then adapted): Instructions for:
     - Parse assessment data from `.specify/migration/analysis.md` and `package-updates.md`
     - Project action classification, web migration candidates, unsupported/out-of-scope resolution
     - Chunked package update plan
     - Output: migration plan with sections per phase

#### 17. `fx-to-dotnet/commands/sdk-convert/convert.md` — *Phase 3: SDK Conversion*
   - **Source**: `agents/sdk-project-conversion.agent.md`
   - **description**: "Convert legacy .NET Framework project file to SDK-style format; validate with build-fix"
   - **tools**: MCP tools (`convert_project_to_sdk_style`), `nuget-package-compat` skill scripts (`getMinimalPackageSet`), file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Initialize, resume check, invoke MCP conversion tool
     - Verify `<Project Sdk=...>` in output
     - Delegate to `speckit.fx-to-dotnet.fix`; let it run full loop
     - Prune redundant PackageReferences via `nuget-package-compat` skill scripts (`getMinimalPackageSet`); re-run build-fix
     - State: conversionStatus, buildStatus

#### 18. `fx-to-dotnet/commands/build-fix/fix.md` — *Cross-cutting: Build/Fix Loop*
   - **Source**: `agents/build-fix.agent.md`
   - **description**: "Run iterative dotnet build → diagnose errors → apply minimal fixes until build succeeds or user stops"
   - **tools**: file read/write, search, ask-questions, terminal
   - **scripts**: `bash/dotnet-build.sh`, `powershell/dotnet-build.ps1`
   - **Body** (copied from source, then adapted): Instructions for:
     - Initialize, resume check, fresh build via script
     - Parse & group errors, fix loop (assess substantiality → apply → verify → retry)
     - Rules: NEVER refactor, NEVER add NuGet deps without confirmation
     - State: errorGroups array

#### 19. `fx-to-dotnet/commands/package-compat/update.md` — *Phase 4: Package Compatibility*
   - **Source**: `agents/package-compat-core.agent.md`
   - **description**: "Execute pre-built chunked package update plan; invoke build-fix after each chunk"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Chunked update + `speckit.fx-to-dotnet.fix` loop
     - Checkpoint policy (alwaysContinue preference)
     - State: chunkResults array

#### 20. `fx-to-dotnet/commands/multitarget/migrate.md` — *Phase 5: Multitarget*
   - **Source**: `agents/multitarget.agent.md`
   - **description**: "Add modern .NET target framework; identify and fix pre-migration API issues; validate with build-fix"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Planning handoffs (BLOCKING GATES)
     - API fix loop referencing policy docs:
       - System.Web → `policies/systemweb-adapters.md`
       - EF6 → `policies/ef6-retention.md`
       - Windows Service → `policies/windows-service.md`
     - Apply TargetFrameworks change, verify with `speckit.fx-to-dotnet.fix`

#### 21. `fx-to-dotnet/commands/web-migrate/migrate.md` — *Phase 6: Web Migration*
   - **Source**: `agents/aspnet-framework-to-aspnetcore-web-migration.agent.md`
   - **description**: "Plan and execute ASP.NET Framework to ASP.NET Core migration; create side-by-side host; port artifacts in slices"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Discovery via `speckit.fx-to-dotnet.inventory`
     - New ASP.NET Core host creation side-by-side
     - Slice-based porting with `speckit.fx-to-dotnet.fix` after each slice
     - Reference policies: `systemweb-adapters.md`, `owin-identity.md`

#### 22. `fx-to-dotnet/commands/detect-project/detect.md` — *Utility: Project Type Detector*
   - **Source**: `agents/project-type-detector.agent.md`
   - **description**: "Read project file; determine SDK-style format, project classification, confidence level, and evidence"
   - **tools**: file read, search
   - **Body** (copied from source, then adapted): Classifications, detection logic, output format

#### 23. `fx-to-dotnet/commands/route-inventory/inventory.md` — *Utility: Route Extraction*
   - **Source**: `agents/legacy-web-route-inventory.agent.md`
   - **description**: "Extract route and endpoint inventory from legacy ASP.NET web project"
   - **tools**: file read, search
   - **Body** (copied from source, then adapted): Extraction scope, output format

#### 24. `fx-to-dotnet/commands/policies/show.md` — *Utility: Policy Viewer*
   - **Source**: new (no fx2dotnet equivalent)
   - **description**: "Display a named migration policy document (ef6-retention, owin-identity, systemweb-adapters, windows-service)"
   - **tools**: file read
   - **Body**: Accepts policy name argument, reads and returns the corresponding `policies/*.md` file

### Phase D: Policy Reference Docs — Copy & Adapt (inside `fx-to-dotnet/policies/`)

Each policy doc is created by copying the corresponding fx2dotnet skill SKILL.md file and applying adaptations.

**Copy source mapping** (fx2dotnet skill → policy file):

| fx2dotnet source file | Target file (inside `fx-to-dotnet/policies/`) |
|---|---|
| `skills/ef6-migration-policy/SKILL.md` | `policies/ef6-retention.md` |
| `skills/owin-identity/SKILL.md` | `policies/owin-identity.md` |
| `skills/systemweb-adapters/SKILL.md` + `skills/systemweb-adapters/references/*.md` | `policies/systemweb-adapters.md` |
| `skills/windows-service-migration/SKILL.md` | `policies/windows-service.md` |

**Policy adaptation checklist**:

1. **Remove SKILL.md frontmatter/metadata** if any; these are plain markdown reference docs
2. **Inline sub-references**: For systemweb-adapters, append `references/behavioral-differences.md`, `references/migrating-modules.md`, `references/migrating-handlers.md`, and `references/property-translations.md` as sections within the single `policies/systemweb-adapters.md`
3. **Agent references → cross-extension command references**: Replace "Build Fix agent" etc. with `speckit.fx-to-dotnet.fix` etc.
4. **State directory**: Replace `.fx2dotnet/` → `.specify/migration/` if referenced

#### 25. `policies/ef6-retention.md`
   - **Source**: `skills/ef6-migration-policy/SKILL.md`
   - EF6 MUST NOT be migrated to EF Core during migration; 6.5+ supports net8.0+ via netstandard2.1

#### 26. `policies/owin-identity.md`
   - **Source**: `skills/owin-identity/SKILL.md`
   - Use `Microsoft.AspNetCore.SystemWebAdapters.Owin` to host OWIN auth pipeline in ASP.NET Core

#### 27. `policies/systemweb-adapters.md`
   - **Source**: `skills/systemweb-adapters/SKILL.md` + all `references/*.md`
   - Adapters as default migration approach; inline behavioral-differences, module/handler migration, property translations

#### 28. `policies/windows-service.md`
   - **Source**: `skills/windows-service-migration/SKILL.md`
   - ServiceBase → BackgroundService + `Microsoft.Extensions.Hosting.WindowsServices`; TFM uses `-windows` suffix

### Phase E: Build Scripts (inside `fx-to-dotnet/scripts/`)

#### 29. `fx-to-dotnet/scripts/bash/dotnet-build.sh` and `fx-to-dotnet/scripts/powershell/dotnet-build.ps1`
   - Accept project/solution path as argument
   - Run `dotnet build` with structured output
   - Return exit code + captured stdout/stderr

### Phase F: Extension READMEs (parallelizable)

#### 30. Create `fx-to-dotnet/README.md`
   Documents:
   - What the extension does
   - All 11 commands with usage
   - Prerequisites (MCP servers needed)
   - State files read/written by each command

### Phase G: Packaging & Validation

#### 31. **Extension validation** (depends on all above)
   - Verify `extension.yml` references all commands correctly
   - Verify each command ID matches `^speckit\.fx-to-dotnet\.[a-z-]+$`
   - Verify version is valid SemVer

#### 32. **Cross-command reference check**
   - Grep all `commands/**/*.md` for `speckit.fx-to-dotnet.*` invoke references
   - Verify each referenced command exists in `extension.yml`

#### 33. **Policy coverage check**
   - Grep all commands for `policies/` references
   - Verify each referenced policy file exists in `fx-to-dotnet/policies/`

#### 34. **Install smoke test**
   ```bash
   specify extension add --dev /path/to/fx-to-dotnet
   ```
   Verify all 11 commands appear in `specify extension list`

#### 35. **Dry-run on sample solution**
   - Invoke `speckit.fx-to-dotnet.orchestrate` on a minimal .NET Framework solution
   - Verify it delegates to `speckit.fx-to-dotnet.assess` for Phase 1

---

## Files to Create (by extension)

| Extension | Files |
|---|---|
| **`fx-to-dotnet/`** | `extension.yml`, `commands/orchestrate.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet/`** | `extension.yml`, `README.md`, `commands/orchestrate/orchestrate.md`, `commands/assess/assess.md`, `commands/plan/plan.md`, `commands/sdk-convert/convert.md`, `commands/build-fix/fix.md`, `commands/package-compat/update.md`, `commands/multitarget/migrate.md`, `commands/web-migrate/migrate.md`, `commands/detect-project/detect.md`, `commands/route-inventory/inventory.md`, `commands/policies/show.md`, `scripts/bash/dotnet-build.sh`, `scripts/powershell/dotnet-build.ps1`, `policies/ef6-retention.md`, `policies/mcp-setup.md`, `policies/owin-identity.md`, `policies/systemweb-adapters.md`, `policies/windows-service.md` |
| **Root** | `README.md`, `LICENSE` |

**Total**: 1 extension, 11 commands, 5 policy docs, 2 build scripts, 2 READMEs, 1 LICENSE

---

## Verification

1. **Extension schema validation**: `extension.yml` passes `specify extension validate`; all command names match `^speckit\.fx-to-dotnet\.[a-z-]+$`
2. **Cross-command reference audit**: Every `speckit.fx-to-dotnet.*` invocation in any command maps to an actual command in `extension.yml`
3. **Policy coverage**: Every policy doc referenced by a command exists in `fx-to-dotnet/policies/`
4. **State convention consistency**: All commands use `.specify/migration/` state paths with consistent file naming
5. **Install test**: Install the extension via `specify extension add --dev`; verify all 11 commands appear
6. **End-to-end dry run**: Orchestrator delegates correctly to the assess command for Phase 1
7. **Policy completeness**: Each policy doc covers all rules from the original fx2dotnet skill

---

## Decisions

| Decision | Rationale |
|---|---|
| **Single extension, many commands** | All 11 commands in one extension; simplifies install, update, and versioning while commands remain organized in their own folders |
| **Monorepo layout** | Extension and repo scripts live in one repo for coordinated development |
| **Bundled policies** | Policy docs live in `fx-to-dotnet/policies/` with a `show-policy` command; avoids duplication |
| **Bundled build scripts** | Scripts live in `fx-to-dotnet/scripts/`, used by the `fix` command |
| **No built-in MCP server** | Only `Microsoft.GitHubCopilot.Modernization.Mcp` is an external MCP dependency; NuGet compat analysis uses bundled skill scripts instead of an MCP server |
| **Command naming** | `speckit.fx-to-dotnet.{verb}` — each command uses a short verb (`fix`, `assess`, `plan`, `convert`, `update-packages`, `multitarget-migrate`, `web-migrate`, `detect`, `inventory`, `show-policy`) |
| **Shared state directory `.specify/migration/`** | All commands read/write the same state files under the solution directory; state format is consistent |
| **Copy-and-adapt from fx2dotnet** | Markdown bodies copied from existing agent/skill files then adapted per checklist |

---

## Further Considerations

1. **Catalog registration**: Register the extension in the Spec Kit community catalog.
2. **Version coordination**: The single extension version applies to all commands; release atomically.
3. **Preset layering**: Teams wanting to customize policies could install a Spec Kit preset that overrides specific policy docs in `fx-to-dotnet` (policies). Out of scope for v0.1.0.
4. **Partial adoption**: Document in the root README which commands can be used standalone (e.g., `speckit.fx-to-dotnet.fix` is useful for any .NET project, not just migrations) vs. which require the full migration flow.
5. **MCP config template**: Include a sample `.mcp.json` in the root README showing the expected `Microsoft.GitHubCopilot.Modernization.Mcp` server configuration.
