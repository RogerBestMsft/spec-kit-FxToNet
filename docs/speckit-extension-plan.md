# Plan: Spec Kit Extension Family for .NET Framework → Modern .NET Migration

## TL;DR

Build a **family of standalone GitHub Spec Kit extensions** (`fx-to-dotnet-*`) that together orchestrate migrating .NET Framework applications to modern .NET (e.g. .NET 10) through a 7-phase workflow. **Each fx2dotnet agent becomes its own independently installable extension**, each providing a single command. A shared policies extension carries the domain migration reference docs. The extensions rely on external MCP servers (no built-in server).

**Source approach**: Copy the markdown instruction bodies from the existing fx2dotnet agent files (`agents/*.md`) and skill files (`skills/*/SKILL.md`) into the new extension command files, then adapt them to Spec Kit command format.

---

## Architecture Overview

### Extension Family

11 extensions total — 10 command extensions (1:1 with fx2dotnet agents) + 1 shared policies extension:

| Extension ID | Role | Source agent | Command name |
|---|---|---|---|
| `fx-to-dotnet` | Orchestrator — drives 7-phase flow | `agents/dotnet-fx-to-modern-dotnet.md` | `speckit.fx-to-dotnet.orchestrate` |
| `fx-to-dotnet-assess` | Phase 1: Assessment | `agents/assessment.agent.md` | `speckit.fx-to-dotnet-assess.assess` |
| `fx-to-dotnet-plan` | Phase 2: Migration planning | `agents/migration-planner.agent.md` | `speckit.fx-to-dotnet-plan.plan` |
| `fx-to-dotnet-sdk-convert` | Phase 3: SDK-style conversion | `agents/sdk-project-conversion.agent.md` | `speckit.fx-to-dotnet-sdk-convert.convert` |
| `fx-to-dotnet-build-fix` | Cross-cutting: build/fix loop | `agents/build-fix.agent.md` | `speckit.fx-to-dotnet-build-fix.fix` |
| `fx-to-dotnet-package-compat` | Phase 4: Package compatibility | `agents/package-compat-core.agent.md` | `speckit.fx-to-dotnet-package-compat.update` |
| `fx-to-dotnet-multitarget` | Phase 5: Multitarget migration | `agents/multitarget.agent.md` | `speckit.fx-to-dotnet-multitarget.migrate` |
| `fx-to-dotnet-web-migrate` | Phase 6: ASP.NET web migration | `agents/aspnet-framework-to-aspnetcore-web-migration.agent.md` | `speckit.fx-to-dotnet-web-migrate.migrate` |
| `fx-to-dotnet-detect-project` | Utility: project type detection | `agents/project-type-detector.agent.md` | `speckit.fx-to-dotnet-detect-project.detect` |
| `fx-to-dotnet-route-inventory` | Utility: legacy route extraction | `agents/legacy-web-route-inventory.agent.md` | `speckit.fx-to-dotnet-route-inventory.inventory` |
| `fx-to-dotnet-policies` | Shared policies + build scripts | `skills/*/SKILL.md` + `skills/systemweb-adapters/references/*` | `speckit.fx-to-dotnet-policies.show` |

### Dependency Graph

```
fx-to-dotnet (orchestrator)
├── fx-to-dotnet-assess
│   ├── fx-to-dotnet-detect-project
│   └── fx-to-dotnet-policies
├── fx-to-dotnet-plan
│   └── fx-to-dotnet-policies
├── fx-to-dotnet-sdk-convert
│   └── fx-to-dotnet-build-fix
│       └── fx-to-dotnet-policies
├── fx-to-dotnet-package-compat
│   └── fx-to-dotnet-build-fix
├── fx-to-dotnet-multitarget
│   ├── fx-to-dotnet-build-fix
│   └── fx-to-dotnet-policies
└── fx-to-dotnet-web-migrate
    ├── fx-to-dotnet-route-inventory
    ├── fx-to-dotnet-build-fix
    └── fx-to-dotnet-policies
```

### Monorepo Layout

All extensions live under `spec-kit/` in the repository and are independently installable:

```
fx2dotnet/                             # Monorepo root
├── README.md
├── LICENSE
│
└── spec-kit/                          # All Spec Kit extensions
    ├── README.md                      # Family overview, phase diagram, install-all instructions
    │
    ├── fx-to-dotnet/                  # Orchestrator extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── orchestrate.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-assess/           # Assessment extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── assess.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-plan/             # Migration planner extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── plan.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-sdk-convert/      # SDK conversion extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── convert.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-build-fix/        # Build/fix loop extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── fix.md
    │   ├── scripts/
    │   │   ├── bash/dotnet-build.sh
    │   │   └── powershell/dotnet-build.ps1
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-package-compat/   # Package compatibility extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── update.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-multitarget/      # Multitarget migration extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── migrate.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-web-migrate/      # ASP.NET web migration extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── migrate.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-detect-project/   # Project type detector extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── detect.md
    │   ├── README.md
    │   └── .extensionignore
    │
    ├── fx-to-dotnet-route-inventory/  # Route inventory extension
    │   ├── extension.yml
    │   ├── commands/
    │   │   └── inventory.md
    │   ├── README.md
    │   └── .extensionignore
    │
    └── fx-to-dotnet-policies/         # Shared policies extension
        ├── extension.yml
        ├── commands/
        │   └── show.md                # Utility: display a named policy
        ├── policies/
        │   ├── ef6-retention.md
        │   ├── owin-identity.md
        │   ├── systemweb-adapters.md
        │   └── windows-service.md
        ├── README.md
        └── .extensionignore
```

---

## Steps

### Phase A: Monorepo Scaffold (foundation — blocks everything)

1. **Create monorepo root files**
   - `README.md` — family overview, 7-phase diagram (Mermaid), dependency graph, bulk install instructions (`specify extension add` for all 11), prerequisites (external MCP servers, .NET SDK)
   - `LICENSE` — MIT (shared across all extensions)

2. **Create shared `.extensionignore` template** — Exclude `tests/`, `.github/`, `*.pyc`, dev artifacts; copied into each extension directory

### Phase B: Extension Manifests (11 `extension.yml` files — parallelizable after Phase A)

Each extension gets its own `extension.yml`. Every manifest follows the same schema:

```yaml
schema_version: "1.0"
extension:
  id: "fx-to-dotnet-{name}"
  name: "{Display Name}"
  version: "0.1.0"
  description: "{What it does}"
  author: "{author}"
  repository: "https://github.com/{org}/fx-to-dotnet-extensions"
  license: "MIT"
requires:
  speckit_version: ">=0.5.0"
  tools: [...]                     # External MCP servers if needed
provides:
  commands:
    - name: "speckit.fx-to-dotnet-{name}.{cmd}"
      file: "commands/{cmd}.md"
```

#### 3. `spec-kit/fx-to-dotnet/extension.yml` — Orchestrator
   - `id: fx-to-dotnet`
   - `requires.tools`: none (delegates to other extensions)
   - `provides.commands`: `speckit.fx-to-dotnet.orchestrate`
   - **README.md**: Describes 7-phase flow, lists all sibling extensions as prerequisites

#### 4. `spec-kit/fx-to-dotnet-assess/extension.yml` — Assessment
   - `id: fx-to-dotnet-assess`
   - `requires.tools`: `Microsoft.GitHubCopilot.AppModernization.Mcp`
   - `provides.commands`: `speckit.fx-to-dotnet-assess.assess`

#### 5. `spec-kit/fx-to-dotnet-plan/extension.yml` — Migration Planner
   - `id: fx-to-dotnet-plan`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-plan.plan`

#### 6. `spec-kit/fx-to-dotnet-sdk-convert/extension.yml` — SDK Conversion
   - `id: fx-to-dotnet-sdk-convert`
   - `requires.tools`: `Microsoft.GitHubCopilot.AppModernization.Mcp`
   - `provides.commands`: `speckit.fx-to-dotnet-sdk-convert.convert`

#### 7. `spec-kit/fx-to-dotnet-build-fix/extension.yml` — Build Fix
   - `id: fx-to-dotnet-build-fix`
   - `requires.tools`: none (uses `dotnet build` via scripts)
   - `provides.commands`: `speckit.fx-to-dotnet-build-fix.fix`

#### 8. `spec-kit/fx-to-dotnet-package-compat/extension.yml` — Package Compatibility
   - `id: fx-to-dotnet-package-compat`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-package-compat.update`

#### 9. `spec-kit/fx-to-dotnet-multitarget/extension.yml` — Multitarget
   - `id: fx-to-dotnet-multitarget`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-multitarget.migrate`

#### 10. `spec-kit/fx-to-dotnet-web-migrate/extension.yml` — Web Migration
   - `id: fx-to-dotnet-web-migrate`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-web-migrate.migrate`

#### 11. `spec-kit/fx-to-dotnet-detect-project/extension.yml` — Project Type Detector
   - `id: fx-to-dotnet-detect-project`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-detect-project.detect`

#### 12. `spec-kit/fx-to-dotnet-route-inventory/extension.yml` — Route Inventory
   - `id: fx-to-dotnet-route-inventory`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-route-inventory.inventory`

#### 13. `spec-kit/fx-to-dotnet-policies/extension.yml` — Shared Policies
   - `id: fx-to-dotnet-policies`
   - `requires.tools`: none
   - `provides.commands`: `speckit.fx-to-dotnet-policies.show` (utility command that displays a named policy doc)

### Phase C: Command Files — Copy & Adapt (11 commands — parallelizable after Phase B)

Each command is created by: (a) copying the markdown body from the corresponding fx2dotnet agent file, (b) replacing the agent YAML frontmatter with Spec Kit command frontmatter, and (c) applying the adaptation checklist.

**Copy source mapping** (fx2dotnet agent → Spec Kit extension/command):

| fx2dotnet source file | Extension | Command file |
|---|---|---|
| `agents/dotnet-fx-to-modern-dotnet.md` | `spec-kit/fx-to-dotnet/` | `commands/orchestrate.md` |
| `agents/assessment.agent.md` | `spec-kit/fx-to-dotnet-assess/` | `commands/assess.md` |
| `agents/migration-planner.agent.md` | `spec-kit/fx-to-dotnet-plan/` | `commands/plan.md` |
| `agents/sdk-project-conversion.agent.md` | `spec-kit/fx-to-dotnet-sdk-convert/` | `commands/convert.md` |
| `agents/build-fix.agent.md` | `spec-kit/fx-to-dotnet-build-fix/` | `commands/fix.md` |
| `agents/package-compat-core.agent.md` | `spec-kit/fx-to-dotnet-package-compat/` | `commands/update.md` |
| `agents/multitarget.agent.md` | `spec-kit/fx-to-dotnet-multitarget/` | `commands/migrate.md` |
| `agents/aspnet-framework-to-aspnetcore-web-migration.agent.md` | `spec-kit/fx-to-dotnet-web-migrate/` | `commands/migrate.md` |
| `agents/project-type-detector.agent.md` | `spec-kit/fx-to-dotnet-detect-project/` | `commands/detect.md` |
| `agents/legacy-web-route-inventory.agent.md` | `spec-kit/fx-to-dotnet-route-inventory/` | `commands/inventory.md` |

**Adaptation checklist** (apply to every copied file):

1. **Frontmatter**: Replace agent YAML (`name`, `description`, `argument-hint`, `tools`, `agents`, `handoffs`) with Spec Kit command YAML (`description`, `tools`, `scripts`)
2. **State directory**: Find-and-replace all `.fx2dotnet/` references → `.fx-to-dotnet/`
3. **Agent invocations → cross-extension command invocations**: Replace "invoke [AgentName] subagent" / "delegate to [AgentName]" with the target extension's command name:
   - "invoke Build Fix subagent" → "invoke `speckit.fx-to-dotnet-build-fix.fix`"
   - "invoke Assessment subagent" → "invoke `speckit.fx-to-dotnet-assess.assess`"
   - "invoke Migration Planner" → "invoke `speckit.fx-to-dotnet-plan.plan`"
   - "invoke SDK-Style Conversion" → "invoke `speckit.fx-to-dotnet-sdk-convert.convert`"
   - "invoke Package Compat Core" → "invoke `speckit.fx-to-dotnet-package-compat.update`"
   - "invoke Multitarget" → "invoke `speckit.fx-to-dotnet-multitarget.migrate`"
   - "invoke ASP.NET Web Migration" → "invoke `speckit.fx-to-dotnet-web-migrate.migrate`"
   - "invoke Project Type Detector" → "invoke `speckit.fx-to-dotnet-detect-project.detect`"
   - "invoke Legacy Web Route Inventory" → "invoke `speckit.fx-to-dotnet-route-inventory.inventory`"
4. **Skill references → policy file references**: Replace "load/follow [skill-name] skill" with "reference `fx-to-dotnet-policies/policies/<name>.md`":
   - "follow ef6-migration-policy skill" → "reference `fx-to-dotnet-policies/policies/ef6-retention.md`"
   - "follow systemweb-adapters skill" → "reference `fx-to-dotnet-policies/policies/systemweb-adapters.md`"
   - "follow windows-service-migration skill" → "reference `fx-to-dotnet-policies/policies/windows-service.md`"
   - "follow owin-identity skill" → "reference `fx-to-dotnet-policies/policies/owin-identity.md`"
5. **Handoffs**: Remove "Commit Changes" handoff references; replace with explicit "checkpoint: commit staged changes" instructions
6. **Terminal execution**: Replace "run via subagent" terminal instructions with "run via script" referencing `fx-to-dotnet-build-fix/scripts/bash/dotnet-build.sh` or `fx-to-dotnet-build-fix/scripts/powershell/dotnet-build.ps1`
7. **Explore agent**: Replace "delegate to Explore subagent" with direct file-read/search tool usage

**State convention** (shared across all extensions): All state persisted under `{solutionDir}/.fx-to-dotnet/`:
- `plan.md` — orchestrator state + migration plan
- `analysis.md` — assessment findings
- `package-updates.md` — package compatibility state
- `preferences.md` — user continuation preferences
- `{ProjectName}.md` — per-project state (sections for SDK Conversion, Build Fix, Multitarget, Web Migration)

#### 14. `spec-kit/fx-to-dotnet/commands/orchestrate.md` — *Orchestrator*
   - **Source**: `agents/dotnet-fx-to-modern-dotnet.md`
   - **description**: "Orchestrate end-to-end .NET Framework to modern .NET migration across 7 phases"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Input resolution: solution path (.sln/.slnx), target framework (default net10.0), state root derivation
     - Resume check: read `.fx-to-dotnet/plan.md`; ask user to resume or start fresh
     - Phase gate enforcement: invokes sibling extensions in order:
       1. `speckit.fx-to-dotnet-assess.assess` → Assessment
       2. `speckit.fx-to-dotnet-plan.plan` → Planning
       3. `speckit.fx-to-dotnet-sdk-convert.convert` → SDK Conversion (layer-by-layer)
       4. `speckit.fx-to-dotnet-package-compat.update` → Package Compat
       5. `speckit.fx-to-dotnet-multitarget.migrate` → Multitarget (layer-by-layer)
       6. `speckit.fx-to-dotnet-web-migrate.migrate` → Web Migration
       7. Completion / Deferred Work
     - Dependency-layer processing: Layer 1 (leaf projects) first, Layer N depends on Layer N-1
     - Commit checkpoint after each phase/sub-step

#### 15. `spec-kit/fx-to-dotnet-assess/commands/assess.md` — *Phase 1: Assessment*
   - **Source**: `agents/assessment.agent.md`
   - **description**: "Gather solution info, identify frameworks, dependencies, blockers; classify projects; audit package compatibility"
   - **tools**: MCP tools (`get_state`, `get_scenarios`, `get_instructions`, `start_task`, `complete_task`, `get_projects_in_topological_order`), `dependency-layers` skill (inline computation), `nuget-package-compat` skill scripts (`findRecommendedUpgrades`), file read/write, search, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Resume check for existing `.fx-to-dotnet/analysis.md`
     - MCP initialization sequence
     - Topological ordering + dependency layer computation
     - Project classification: invoke `speckit.fx-to-dotnet-detect-project.detect` per project
     - NuGet feed resolution + package discovery + compatibility cards
     - Out-of-scope identification: reference policy docs from `fx-to-dotnet-policies`
     - Output: persist `analysis.md` and `package-updates.md`

#### 16. `spec-kit/fx-to-dotnet-plan/commands/plan.md` — *Phase 2: Planning*
   - **Source**: `agents/migration-planner.agent.md`
   - **description**: "Synthesize assessment findings into actionable, layered migration plan with chunked package updates"
   - **tools**: file read/write, search
   - **Body** (copied from source, then adapted): Instructions for:
     - Parse assessment data from `.fx-to-dotnet/analysis.md` and `package-updates.md`
     - Project action classification, web migration candidates, unsupported/out-of-scope resolution
     - Chunked package update plan
     - Output: migration plan with sections per phase

#### 17. `spec-kit/fx-to-dotnet-sdk-convert/commands/convert.md` — *Phase 3: SDK Conversion*
   - **Source**: `agents/sdk-project-conversion.agent.md`
   - **description**: "Convert legacy .NET Framework project file to SDK-style format; validate with build-fix"
   - **tools**: MCP tools (`convert_project_to_sdk_style`), `nuget-package-compat` skill scripts (`getMinimalPackageSet`), file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Initialize, resume check, invoke MCP conversion tool
     - Verify `<Project Sdk=...>` in output
     - Delegate to `speckit.fx-to-dotnet-build-fix.fix`; let it run full loop
     - Prune redundant PackageReferences via `nuget-package-compat` skill scripts (`getMinimalPackageSet`); re-run build-fix
     - State: conversionStatus, buildStatus

#### 18. `spec-kit/fx-to-dotnet-build-fix/commands/fix.md` — *Cross-cutting: Build/Fix Loop*
   - **Source**: `agents/build-fix.agent.md`
   - **description**: "Run iterative dotnet build → diagnose errors → apply minimal fixes until build succeeds or user stops"
   - **tools**: file read/write, search, ask-questions, terminal
   - **scripts**: `bash/dotnet-build.sh`, `powershell/dotnet-build.ps1`
   - **Body** (copied from source, then adapted): Instructions for:
     - Initialize, resume check, fresh build via script
     - Parse & group errors, fix loop (assess substantiality → apply → verify → retry)
     - Rules: NEVER refactor, NEVER add NuGet deps without confirmation
     - State: errorGroups array

#### 19. `spec-kit/fx-to-dotnet-package-compat/commands/update.md` — *Phase 4: Package Compatibility*
   - **Source**: `agents/package-compat-core.agent.md`
   - **description**: "Execute pre-built chunked package update plan; invoke build-fix after each chunk"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Chunked update + `speckit.fx-to-dotnet-build-fix.fix` loop
     - Checkpoint policy (alwaysContinue preference)
     - State: chunkResults array

#### 20. `spec-kit/fx-to-dotnet-multitarget/commands/migrate.md` — *Phase 5: Multitarget*
   - **Source**: `agents/multitarget.agent.md`
   - **description**: "Add modern .NET target framework; identify and fix pre-migration API issues; validate with build-fix"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Planning handoffs (BLOCKING GATES)
     - API fix loop referencing policy docs:
       - System.Web → `fx-to-dotnet-policies/policies/systemweb-adapters.md`
       - EF6 → `fx-to-dotnet-policies/policies/ef6-retention.md`
       - Windows Service → `fx-to-dotnet-policies/policies/windows-service.md`
     - Apply TargetFrameworks change, verify with `speckit.fx-to-dotnet-build-fix.fix`

#### 21. `spec-kit/fx-to-dotnet-web-migrate/commands/migrate.md` — *Phase 6: Web Migration*
   - **Source**: `agents/aspnet-framework-to-aspnetcore-web-migration.agent.md`
   - **description**: "Plan and execute ASP.NET Framework to ASP.NET Core migration; create side-by-side host; port artifacts in slices"
   - **tools**: file read/write, search, ask-questions, invoke-command
   - **Body** (copied from source, then adapted): Instructions for:
     - Discovery via `speckit.fx-to-dotnet-route-inventory.inventory`
     - New ASP.NET Core host creation side-by-side
     - Slice-based porting with `speckit.fx-to-dotnet-build-fix.fix` after each slice
     - Reference policies: `systemweb-adapters.md`, `owin-identity.md`

#### 22. `spec-kit/fx-to-dotnet-detect-project/commands/detect.md` — *Utility: Project Type Detector*
   - **Source**: `agents/project-type-detector.agent.md`
   - **description**: "Read project file; determine SDK-style format, project classification, confidence level, and evidence"
   - **tools**: file read, search
   - **Body** (copied from source, then adapted): Classifications, detection logic, output format

#### 23. `spec-kit/fx-to-dotnet-route-inventory/commands/inventory.md` — *Utility: Route Extraction*
   - **Source**: `agents/legacy-web-route-inventory.agent.md`
   - **description**: "Extract route and endpoint inventory from legacy ASP.NET web project"
   - **tools**: file read, search
   - **Body** (copied from source, then adapted): Extraction scope, output format

#### 24. `spec-kit/fx-to-dotnet-policies/commands/show.md` — *Utility: Policy Viewer*
   - **Source**: new (no fx2dotnet equivalent)
   - **description**: "Display a named migration policy document (ef6-retention, owin-identity, systemweb-adapters, windows-service)"
   - **tools**: file read
   - **Body**: Accepts policy name argument, reads and returns the corresponding `policies/*.md` file

### Phase D: Policy Reference Docs — Copy & Adapt (inside `spec-kit/fx-to-dotnet-policies`)

Each policy doc is created by copying the corresponding fx2dotnet skill SKILL.md file and applying adaptations.

**Copy source mapping** (fx2dotnet skill → policy file):

| fx2dotnet source file | Target file (inside `spec-kit/fx-to-dotnet-policies/`) |
|---|---|
| `skills/ef6-migration-policy/SKILL.md` | `policies/ef6-retention.md` |
| `skills/owin-identity/SKILL.md` | `policies/owin-identity.md` |
| `skills/systemweb-adapters/SKILL.md` + `skills/systemweb-adapters/references/*.md` | `policies/systemweb-adapters.md` |
| `skills/windows-service-migration/SKILL.md` | `policies/windows-service.md` |

**Policy adaptation checklist**:

1. **Remove SKILL.md frontmatter/metadata** if any; these are plain markdown reference docs
2. **Inline sub-references**: For systemweb-adapters, append `references/behavioral-differences.md`, `references/migrating-modules.md`, `references/migrating-handlers.md`, and `references/property-translations.md` as sections within the single `policies/systemweb-adapters.md`
3. **Agent references → cross-extension command references**: Replace "Build Fix agent" etc. with `speckit.fx-to-dotnet-build-fix.fix` etc.
4. **State directory**: Replace `.fx2dotnet/` → `.fx-to-dotnet/` if referenced

#### 25. `fx-to-dotnet-policies/policies/ef6-retention.md`
   - **Source**: `skills/ef6-migration-policy/SKILL.md`
   - EF6 MUST NOT be migrated to EF Core during migration; 6.5+ supports net8.0+ via netstandard2.1

#### 26. `fx-to-dotnet-policies/policies/owin-identity.md`
   - **Source**: `skills/owin-identity/SKILL.md`
   - Use `Microsoft.AspNetCore.SystemWebAdapters.Owin` to host OWIN auth pipeline in ASP.NET Core

#### 27. `fx-to-dotnet-policies/policies/systemweb-adapters.md`
   - **Source**: `skills/systemweb-adapters/SKILL.md` + all `references/*.md`
   - Adapters as default migration approach; inline behavioral-differences, module/handler migration, property translations

#### 28. `fx-to-dotnet-policies/policies/windows-service.md`
   - **Source**: `skills/windows-service-migration/SKILL.md`
   - ServiceBase → BackgroundService + `Microsoft.Extensions.Hosting.WindowsServices`; TFM uses `-windows` suffix

### Phase E: Build Scripts (inside `fx-to-dotnet-build-fix`)

#### 29. `fx-to-dotnet-build-fix/scripts/bash/dotnet-build.sh` and `fx-to-dotnet-build-fix/scripts/powershell/dotnet-build.ps1`
   - Accept project/solution path as argument
   - Run `dotnet build` with structured output
   - Return exit code + captured stdout/stderr

### Phase F: Extension READMEs (parallelizable)

#### 30. Create per-extension `README.md` files (11 total)
   Each README documents:
   - What the extension does
   - Command name and usage
   - Prerequisites (which sibling extensions must be installed, which MCP servers are needed)
   - State files it reads/writes

### Phase G: Packaging & Validation

#### 31. **Per-extension validation** (depends on all above)
   For each extension:
   - Verify `extension.yml` references its command correctly
   - Verify command ID matches `^speckit\.fx-to-dotnet(-[a-z-]+)?\.[a-z-]+$`
   - Verify version is valid SemVer

#### 32. **Cross-extension reference check**
   - Grep all `commands/*.md` across all extensions for `speckit.fx-to-dotnet-*` invoke references
   - Verify each referenced command exists in the corresponding sibling extension's `extension.yml`

#### 33. **Policy coverage check**
   - Grep all commands for `fx-to-dotnet-policies/policies/` references
   - Verify each referenced policy file exists in `fx-to-dotnet-policies/policies/`

#### 34. **Install smoke test**
   ```bash
   # Install all extensions
   for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan fx-to-dotnet-sdk-convert \
              fx-to-dotnet-build-fix fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
              fx-to-dotnet-web-migrate fx-to-dotnet-detect-project fx-to-dotnet-route-inventory \
              fx-to-dotnet-policies; do
     specify extension add --dev /path/to/$ext
   done
   ```
   Verify all 11 commands appear in `specify extension list`

#### 35. **Dry-run on sample solution**
   - Invoke `speckit.fx-to-dotnet.orchestrate` on a minimal .NET Framework solution
   - Verify it delegates to `speckit.fx-to-dotnet-assess.assess` for Phase 1

---

## Files to Create (by extension)

| Extension | Files |
|---|---|
| **`fx-to-dotnet/`** | `extension.yml`, `commands/orchestrate.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-assess/`** | `extension.yml`, `commands/assess.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-plan/`** | `extension.yml`, `commands/plan.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-sdk-convert/`** | `extension.yml`, `commands/convert.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-build-fix/`** | `extension.yml`, `commands/fix.md`, `scripts/bash/dotnet-build.sh`, `scripts/powershell/dotnet-build.ps1`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-package-compat/`** | `extension.yml`, `commands/update.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-multitarget/`** | `extension.yml`, `commands/migrate.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-web-migrate/`** | `extension.yml`, `commands/migrate.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-detect-project/`** | `extension.yml`, `commands/detect.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-route-inventory/`** | `extension.yml`, `commands/inventory.md`, `README.md`, `.extensionignore` |
| **`fx-to-dotnet-policies/`** | `extension.yml`, `commands/show.md`, `policies/ef6-retention.md`, `policies/owin-identity.md`, `policies/systemweb-adapters.md`, `policies/windows-service.md`, `README.md`, `.extensionignore` |
| **Root** | `README.md`, `LICENSE` |

**Total**: 11 extensions, 11 commands, 4 policy docs, 2 build scripts, 11 READMEs + 1 root README, 1 LICENSE = ~42 files

---

## Verification

1. **Per-extension schema validation**: Each `extension.yml` passes `specify extension validate`; IDs match `^fx-to-dotnet(-[a-z-]+)?$`; command names match `^speckit\.<ext-id>\.[a-z-]+$`
2. **Cross-extension reference audit**: Every `speckit.fx-to-dotnet-*.xxx` invocation in any command maps to an actual command in a sibling extension
3. **Policy coverage**: Every policy doc referenced by a command exists in `fx-to-dotnet-policies/policies/`
4. **State convention consistency**: All extensions use `.fx-to-dotnet/` state paths with consistent file naming
5. **Bulk install test**: Install all 11 extensions via `specify extension add --dev`; verify all commands appear
6. **End-to-end dry run**: Orchestrator delegates correctly to Phase 1 assessment extension
7. **Policy completeness**: Each policy doc covers all rules from the original fx2dotnet skill

---

## Decisions

| Decision | Rationale |
|---|---|
| **Each agent = its own extension** | Maximum modularity; extensions can be installed/updated independently; teams can adopt individual phases without the full suite |
| **Monorepo layout** | All 11 extensions live in one repo for coordinated development, but each directory is independently installable |
| **Shared policies extension** | `fx-to-dotnet-policies` carries all 4 policy docs with a `show` utility command; avoids duplicating policies across extensions |
| **Build scripts in build-fix extension** | Scripts are only used by the build-fix command, so they live in that extension |
| **No built-in MCP server** | Only `Microsoft.GitHubCopilot.AppModernization.Mcp` is an external MCP dependency; NuGet compat analysis uses bundled skill scripts instead of an MCP server |
| **Cross-extension command naming** | `speckit.{ext-id}.{verb}` — each extension exposes one command with a short verb (`fix`, `assess`, `plan`, `convert`, `update`, `migrate`, `detect`, `inventory`, `show`) |
| **Shared state directory `.fx-to-dotnet/`** | All extensions read/write the same state files under the solution directory; state format is consistent across extensions |
| **Copy-and-adapt from fx2dotnet** | Markdown bodies copied from existing agent/skill files then adapted per checklist |

---

## Further Considerations

1. **Catalog registration**: Register all 11 extensions in the Spec Kit community catalog as a family; consider a catalog group for one-click install of the complete suite.
2. **Version coordination**: All extensions should share the same version number and be released together to avoid compatibility drift between sibling extensions.
3. **Preset layering**: Teams wanting to customize policies could install a Spec Kit preset that overrides specific policy docs in `fx-to-dotnet-policies`. Out of scope for v0.1.0.
4. **Partial adoption**: Document in the root README which extensions can be used standalone (e.g., `fx-to-dotnet-build-fix` is useful for any .NET project, not just migrations) vs. which require the full suite.
5. **MCP config template**: Include a sample `.mcp.json` in the root README showing the expected `Microsoft.GitHubCopilot.AppModernization.Mcp` server configuration.
