# Plan: Replace Swick.Mcp.Fx2dotnet MCP Server with Copilot Customizations

## TL;DR

Remove the `src/fx2dotnet/` MCP server project and replace its 3 tools with Copilot customization primitives — a **skill with algorithm instructions** for `ComputeDependencyLayers`, and a **skill with bundled PowerShell/Bash scripts** (using NuGet v3 REST API) for `FindRecommendedPackageUpgrades` and `GetMinimalPackageSet`. A new helper subagent provides script execution. Update all consuming agents, spec-kit files, config, and docs.

---

## Motivation

The `Swick.Mcp.Fx2dotnet` MCP server is the only buildable project in this repo. It requires .NET 10 preview SDK, NuGet package publishing, and `dnx` to run — all for 3 tools that can be expressed as agent instructions and shell scripts. Replacing it with Copilot customization primitives removes the build/publish dependency chain and keeps all migration logic in the same layer as the agents that consume it.

---

## Current State

The `Swick.Mcp.Fx2dotnet` MCP server (in `src/fx2dotnet/`) is a .NET 10 console app using `ModelContextProtocol` and `NuGet.Protocol`. It communicates via stdio JSON-RPC and exposes 3 tools:

| Tool | Nature | Consumers |
|------|--------|-----------|
| `ComputeDependencyLayers` | Pure algorithm — topological layer grouping via iterative graph reduction | `assessment.agent.md`, `migration-planner.agent.md` (reads output) |
| `FindRecommendedPackageUpgrades` | NuGet v3 API queries — minimum version discovery, legacy flag detection | `assessment.agent.md` |
| `GetMinimalPackageSet` | NuGet v3 API queries — transitive dependency pruning | `sdk-project-conversion.agent.md` |

**46 total references** across 29 files (agents, spec-kit, README, config).

### What Each Tool Does

**ComputeDependencyLayers** — Accepts a list of projects with their in-solution dependency edges. Uses iterative graph reduction: finds all projects with zero in-scope dependencies (Layer 1), removes them from the graph, repeats. Each layer's projects are independent and can be processed in parallel. Detects cycles (projects remaining after no more zero-dependency nodes exist). Returns layers as `{ layers: [{layer, projects[]}], unresolvedCycles?, error? }`.

**FindRecommendedPackageUpgrades** — For each input package (ID + current version), queries NuGet v3 feeds to find the minimum version that supports modern .NET (netstandard, netcoreapp, net5.0+). Also downloads the current version's .nupkg to check for legacy patterns: `content/` folder (legacy content deployment, incompatible with `PackageReference`) and `tools/install.ps1` (silent no-op under `PackageReference`). Returns recommendations with minimum version, supported TFMs, feed source, and legacy flags.

**GetMinimalPackageSet** — For each input package (ID + version), queries NuGet v3 feeds for its dependency groups under modern TFMs. If package A declares a dependency on package B, and both A and B are in the input set, B is marked as transitively provided and can be removed as a direct `PackageReference`. Returns the minimal keep set and the removed set with provenance.

---

## Replacement Strategy

### Tool-by-Tool Mapping

```
┌──────────────────────────────────┐     ┌────────────────────────────────────────┐
│  Current (MCP Server)            │     │  Replacement (Copilot Customizations)  │
├──────────────────────────────────┤     ├────────────────────────────────────────┤
│ ComputeDependencyLayers          │ ──► │ skills/dependency-layers/SKILL.md      │
│   (C# algorithm in-process)      │     │   (agent follows algorithm inline)     │
├──────────────────────────────────┤     ├────────────────────────────────────────┤
│ FindRecommendedPackageUpgrades   │ ──► │ skills/nuget-package-compat/           │
│   (C# + NuGet.Protocol)         │     │   scripts/ps1 + bash (NuGet v3 REST)  │
│                                  │     │   + agents/nuget-analysis.agent.md     │
├──────────────────────────────────┤     ├────────────────────────────────────────┤
│ GetMinimalPackageSet             │ ──► │ skills/nuget-package-compat/           │
│   (C# + NuGet.Protocol)         │     │   scripts/ps1 + bash (NuGet v3 REST)  │
│                                  │     │   + agents/nuget-analysis.agent.md     │
└──────────────────────────────────┘     └────────────────────────────────────────┘
```

### Why These Primitives

| Tool | Primitive | Rationale |
|------|-----------|-----------|
| `ComputeDependencyLayers` | **Skill (instructions only)** | Pure algorithm on small data (solution-scale, typically <50 projects). Step-by-step instructions with a worked example are sufficient for an agent to execute inline. No external I/O needed. |
| `FindRecommendedPackageUpgrades` | **Skill + scripts + subagent** | Requires HTTP requests to NuGet feeds — agents cannot make HTTP calls directly. Scripts call the NuGet v3 REST API. A dedicated subagent with `execute` tool runs the scripts, following the project convention that terminal commands run via subagent. |
| `GetMinimalPackageSet` | **Skill + scripts + subagent** | Same rationale as above — HTTP access to NuGet v3 feeds, reuses the same subagent. |

---

## Implementation Plan

### Phase 1: Create Replacement Skills and Agent

#### Step 1 — `skills/dependency-layers/SKILL.md`

Create a skill that encodes the iterative graph reduction algorithm as agent-executable instructions.

**Contents:**
- When to use: computing dependency layers from a project dependency graph
- Algorithm steps (matching the current C# implementation exactly):
  1. Normalize all project paths: lowercase + forward slashes
  2. Build adjacency map: each project → set of in-scope dependencies
  3. Iterative reduction: find all projects with zero remaining dependencies → Layer N, remove from graph, repeat
  4. Cycle detection: any projects remaining after no zero-dependency nodes exist
  5. Output: layers sorted by layer number, projects within each layer sorted alphabetically
- Input/output JSON schema (matching current MCP tool)
- Worked example with sample input → expected output (including a cycle case)

**Key behaviors to preserve:**
- Path normalization: case-insensitive comparison, backslashes → forward slashes
- Duplicate project entries: merge dependencies
- Dependencies outside the input set: silently ignored
- Self-dependencies: silently ignored
- Stable ordering: alphabetical by original path within each layer

#### Step 2 — `skills/nuget-package-compat/` Skill with Scripts

Create a skill with bundled scripts that replicate the NuGet query functionality.

**New files:**

```
skills/nuget-package-compat/
├── SKILL.md
└── scripts/
    ├── powershell/
    │   ├── Find-RecommendedPackageUpgrades.ps1
    │   └── Get-MinimalPackageSet.ps1
    └── bash/
        ├── find-recommended-package-upgrades.sh
        └── get-minimal-package-set.sh
```

**`SKILL.md` contents:**
- When to use: NuGet package compatibility analysis during .NET migration assessment or SDK-style project conversion
- Script invocation procedures (PowerShell on Windows, Bash on macOS/Linux)
- Input JSON schema for each script (matching current MCP tool parameters)
- Output JSON schema for each script (matching current MCP tool responses)
- Error handling: scripts always output valid JSON with `reason`/`error` fields on failure
- How to interpret results: what each field means, how compatibility cards map to migration decisions

**`Find-RecommendedPackageUpgrades` script behavior:**

| Step | Current C# | Replacement script |
|------|-----------|-------------------|
| Resolve NuGet feeds | `NuGet.Configuration.Settings` — recursive parent dir search, `clear`/add semantics | Read nearest `nuget.config` from workspace dir upward, parse `<packageSources>`, fall back to `https://api.nuget.org/v3/index.json` |
| Discover service index | Implicit via `NuGet.Protocol` | `GET {source}/index.json` → find `RegistrationsBaseUrl` resource |
| Find minimum modern version | Enumerate all versions via `PackageMetadataResource`, check each version's dependency groups for netstandard/netcoreapp/net5.0+ TFMs | `GET {registrationsBase}/{id}/index.json` → page through catalog entries, inspect `dependencyGroups[].targetFramework` |
| Check legacy flags | Download .nupkg as stream, inspect file listing for `content/` and `tools/install.ps1` | `GET {packageContent}/{id}/{version}/{id}.{version}.nupkg` → pipe to zip listing (`Expand-Archive` / `unzip -l`), check paths |
| Return results | JSON serialization of `PackageUpgradeRecommendationResult` | JSON output matching same schema |

**Input (stdin):**
```json
{
  "workspaceDirectory": "C:/path/to/solution",
  "nugetConfigPath": null,
  "packages": [
    { "packageId": "Newtonsoft.Json", "currentVersion": "12.0.3" },
    { "packageId": "Castle.Windsor", "currentVersion": "5.1.1" }
  ],
  "includePrerelease": false
}
```

**Output (stdout):**
```json
{
  "recommendations": [
    {
      "packageId": "Castle.Windsor",
      "currentVersion": "5.1.1",
      "minimumSupportedVersion": "6.0.0",
      "supports": ["net6.0", "netstandard2.1"],
      "supportFamilies": ["netcore", "netstandard"],
      "feed": "https://api.nuget.org/v3/index.json",
      "hasLegacyContentFolder": false,
      "hasInstallScript": false,
      "reason": null
    }
  ],
  "reason": null
}
```

**`Get-MinimalPackageSet` script behavior:**

| Step | Current C# | Replacement script |
|------|-----------|-------------------|
| Resolve feeds | Same as above | Same as above |
| Get dependency groups | `PackageMetadataResource.GetMetadataAsync` for exact version, extract modern-TFM dependency groups | `GET {registrationsBase}/{id}/index.json` → find exact version entry → read `dependencyGroups` for modern TFMs |
| Build transitive map | Check if any dependency ID is in the input set → mark as provided | Same logic |
| Return results | JSON serialization of `MinimalPackageSetResult` | JSON output matching same schema |

**Input (stdin):**
```json
{
  "workspaceDirectory": "C:/path/to/solution",
  "nugetConfigPath": null,
  "packages": [
    { "packageId": "Microsoft.Extensions.Hosting", "currentVersion": "8.0.0" },
    { "packageId": "Microsoft.Extensions.DependencyInjection", "currentVersion": "8.0.0" }
  ]
}
```

**Output (stdout):**
```json
{
  "keep": [
    { "packageId": "Microsoft.Extensions.Hosting", "currentVersion": "8.0.0" }
  ],
  "removed": [
    {
      "packageId": "Microsoft.Extensions.DependencyInjection",
      "currentVersion": "8.0.0",
      "providedBy": ["Microsoft.Extensions.Hosting"]
    }
  ],
  "reason": null
}
```

#### Step 3 — `agents/nuget-analysis.agent.md` Helper Subagent

Create a non-user-invocable subagent that executes the NuGet scripts.

```yaml
---
name: NuGet Analysis
description: "Use when performing NuGet package compatibility analysis, package upgrade recommendations, minimal package set computation, or transitive dependency pruning. Runs NuGet v3 REST API scripts and returns structured JSON results."
tools: [execute, read]
user-invocable: false
---
```

**Behavior:**
- Receives a request specifying which operation (`findRecommendedUpgrades` or `getMinimalPackageSet`) and the JSON input
- Loads the `nuget-package-compat` skill for invocation procedures
- Detects OS: Windows → PowerShell scripts, macOS/Linux → Bash scripts
- Pipes JSON input to the appropriate script via stdin
- Returns the script's JSON output to the calling agent

---

### Phase 2: Update Consuming Agents

#### Step 4 — Update `agents/assessment.agent.md`

**Frontmatter changes:**
```yaml
# Before
tools: [microsoft.githubcopilot.appmodernization.mcp/*, Swick.Mcp.Fx2dotnet/*, read, search, agent, edit, vscode/askQuestions]
agents: ['Explore', 'Project Type Detector']

# After
tools: [microsoft.githubcopilot.appmodernization.mcp/*, read, search, agent, edit, vscode/askQuestions]
agents: ['Explore', 'Project Type Detector', 'NuGet Analysis']
```

**Section 5b (Compute Dependency Layers):** Replace the `ComputeDependencyLayers` MCP tool call with instructions to follow the `dependency-layers` skill. The agent computes layers inline from the project dependency data already gathered via `get_project_dependencies`.

**Section 7c (Ground Compatibility with NuGet Data):** Replace the `FindRecommendedPackageUpgrades` MCP tool call with delegation to the **NuGet Analysis** subagent. Pass the same JSON payload. The subagent runs the `Find-RecommendedPackageUpgrades` script and returns structured results.

#### Step 5 — Update `agents/sdk-project-conversion.agent.md`

**Frontmatter changes:**
```yaml
# Before
tools: [..., Swick.Mcp.Fx2dotnet/GetMinimalPackageSet, ...]

# After (remove MCP tool, add agent + agents list)
tools: [..., agent, ...]
agents: ['Build Fix', 'NuGet Analysis']
```

**Section 6 (Prune Redundant Package References):** Replace `GetMinimalPackageSet` MCP tool call with delegation to the **NuGet Analysis** subagent. Pass the same JSON payload. The subagent runs the `Get-MinimalPackageSet` script and returns structured results.

#### Step 6 — Update `agents/migration-planner.agent.md`

Minor text update only — the planner already reads layers from `analysis.md`, not from a tool call. Update the inputs description that references `ComputeDependencyLayers` to note the data comes from the assessment report's Dependency Layers section.

---

### Phase 3: Update Configuration and Documentation

#### Step 7 — Update `.mcp.json`

Remove the `Swick.Mcp.Fx2dotnet` server entry entirely:

```json
{
  "mcpServers": {
    "Microsoft.GitHubCopilot.AppModernization.Mcp": {
      "type": "stdio",
      "command": "dnx",
      "args": [
        "Microsoft.GitHubCopilot.AppModernization.Mcp@1.0.903-preview1",
        "--yes",
        "--source",
        "https://api.nuget.org/v3/index.json"
      ],
      "tools": ["*"]
    }
  }
}
```

#### Step 8 — Update `.github/copilot-instructions.md`

- Remove `Swick.Mcp.Fx2dotnet` from the MCP servers bullet
- Replace the `src/fx2dotnet/` source code line with references to the new skills:
  - `skills/dependency-layers/` — dependency layer computation algorithm
  - `skills/nuget-package-compat/` — NuGet package compatibility analysis scripts

#### Step 9 — Update `README.md`

- Remove `ComputeDependencyLayers` MCP tool description (~line 225)
- Remove `Swick.Mcp.Fx2dotnet` MCP server description (~line 289)
- Add brief mention of the replacement skills and subagent in the architecture section

---

### Phase 4: Update Spec-Kit

#### Step 10 — Update Spec-Kit Extension Files

10 files need updates to replace MCP tool references with skill/agent equivalents:

| File | Change |
|------|--------|
| `spec-kit/README.md` | Remove `Swick.Mcp.Fx2dotnet` references |
| `spec-kit/docs/speckit-extension-plan.md` | Update tool references for assess and sdk-convert extensions |
| `spec-kit/docs/speckit-deployment-plan.md` | Remove MCP server packaging/deployment references |
| `spec-kit/fx-to-dotnet-assess/README.md` | Remove MCP dependency |
| `spec-kit/fx-to-dotnet-assess/extension.yml` | Remove MCP dependency from `requires` |
| `spec-kit/fx-to-dotnet-assess/commands/assess.md` | Replace `Swick.Mcp.Fx2dotnet/*` tools with skill/agent references |
| `spec-kit/fx-to-dotnet-plan/commands/plan.md` | Update `ComputeDependencyLayers` reference |
| `spec-kit/fx-to-dotnet-sdk-convert/README.md` | Remove MCP dependency |
| `spec-kit/fx-to-dotnet-sdk-convert/extension.yml` | Remove MCP dependency from `requires` |
| `spec-kit/fx-to-dotnet-sdk-convert/commands/convert.md` | Replace `Swick.Mcp.Fx2dotnet/GetMinimalPackageSet` with skill/agent references |

---

### Phase 5: Remove MCP Server Source (Manual Review Gate)

> **HOLD**: Do not execute Phase 5 until a manual review of Phases 1–4 has been completed and approved. The replacement skills, scripts, subagent, and all reference updates must be verified working before the MCP server source is removed. A reviewer must explicitly sign off before proceeding.

#### Step 11 — Delete `src/fx2dotnet/` (after manual review)

After manual review confirms the replacements are correct and functional, remove the entire directory tree:

```
src/fx2dotnet/
├── .mcp/server.json
├── fx2dotnet.csproj
├── Program.cs
├── Tools.cs
├── Models/
│   ├── DependencyModels.cs
│   └── PackageModels.cs
└── Services/
    ├── DependencyLayerComputer.cs
    └── NuGetPackageSupportService.cs
```

#### Step 12 — Clean Up Build Infrastructure (after manual review)

Only proceed after the same manual review sign-off as Step 11.

| File | Action | Reason |
|------|--------|--------|
| `fx2dotnet.slnx` | **Delete** | Only solution in the repo; no buildable projects remain |
| `Directory.Build.props` | **Evaluate → likely delete** | Sets `ArtifactsPath` for build output — no longer needed without buildable projects |
| `Directory.Build.targets` | **Evaluate → likely delete** | May contain shared build config — no longer needed |
| `global.json` | **Evaluate → likely delete** | Pins .NET 10 preview SDK for the MCP server build |
| `CHANGELOG.md` | **Update** | Add entry for removal of MCP server |

---

## Dependency Graph

```
Phase 1 (Create)
├── Step 1: skills/dependency-layers/
├── Step 2: skills/nuget-package-compat/     ← parallel with Step 1
└── Step 3: agents/nuget-analysis.agent.md   ← depends on Step 2

Phase 2 (Update Agents)                      ← depends on Phase 1
├── Step 4: assessment.agent.md              ← depends on Steps 1, 3
├── Step 5: sdk-project-conversion.agent.md  ← depends on Steps 2, 3  ← parallel
└── Step 6: migration-planner.agent.md       ← depends on Step 1      ← parallel

Phase 3 (Config & Docs)                      ← parallel with Phase 2
├── Step 7: .mcp.json
├── Step 8: copilot-instructions.md          ← parallel
└── Step 9: README.md                        ← parallel

Phase 4 (Spec-Kit)                           ← parallel with Phases 2-3
└── Step 10: 10 spec-kit files

Phase 5 (Remove) ← BLOCKED until manual review of Phases 1-4 is approved
├── ⛔ Manual review gate: reviewer must sign off
├── Step 11: delete src/fx2dotnet/           ← after manual review approval
└── Step 12: clean up build infra            ← depends on Step 11
```

---

## Verification Checklist

| # | Check | Expected Result |
|---|-------|-----------------|
| 1 | Grep `Swick.Mcp.Fx2dotnet` across repo | 0 matches |
| 2 | Grep `FindRecommendedPackageUpgrades\|GetMinimalPackageSet\|ComputeDependencyLayers` | All remaining refs point to skills/agent, not MCP |
| 3 | Validate `skills/dependency-layers/SKILL.md` frontmatter | `name: dependency-layers`, description contains "dependency layer" keywords |
| 4 | Validate `skills/nuget-package-compat/SKILL.md` frontmatter | `name: nuget-package-compat`, description contains "NuGet" keywords |
| 5 | Validate `agents/nuget-analysis.agent.md` frontmatter | `user-invocable: false`, `tools: [execute, read]` |
| 6 | Test `Find-RecommendedPackageUpgrades` script | Pipe sample JSON → valid output schema with real NuGet data |
| 7 | Test `Get-MinimalPackageSet` script | Pipe known transitive pair (e.g., `Microsoft.Extensions.Hosting` → `Microsoft.Extensions.DependencyInjection`) → correct keep/removed |
| 8 | Test `dependency-layers` skill instructions | Agent produces correct layers for sample graph with cycles |
| 9 | Validate `.mcp.json` | Valid JSON, only `Microsoft.GitHubCopilot.AppModernization.Mcp` remaining |
| 10 | No orphan build files | `fx2dotnet.slnx` removed, no dangling references |

---

## Decisions and Rationale

| Decision | Rationale |
|----------|-----------|
| `ComputeDependencyLayers` → skill instructions (not a script) | Pure algorithm on small data (solution-scale). Step-by-step agent instructions with a worked example avoid script I/O complexity. |
| NuGet tools → scripts + helper subagent | NuGet v3 REST API queries require HTTP access agents don't have. A dedicated subagent with `execute` tool runs the scripts, matching the project convention of "terminal via subagent." |
| Raw HTTP (NuGet v3 REST API) for scripts | No dependency on dotnet SDK for script execution. Replicates exact behavior. Portable across environments. |
| Both PowerShell and Bash variants | Cross-platform support per project conventions. |
| JSON I/O contract preserved | Scripts accept/return JSON matching current MCP tool schemas exactly, minimizing changes to agent workflow prose. |
| Spec-kit updates included | Full consistency across the repo. All references updated in the same pass. |

---

## Open Questions

1. **nuget.config resolution fidelity** — The current C# code uses `NuGet.Configuration` for recursive parent-directory search with `clear`/add semantics. Scripts will use a simplified version (nearest `nuget.config` + nuget.org fallback). Should we invest in full-fidelity config parsing, or accept simplified resolution with a documented limitation?

2. **Legacy flag detection scope** — Checking `HasLegacyContentFolder` and `HasInstallScript` requires downloading the full .nupkg and inspecting its file listing. This adds network time and script complexity. Is this feature essential for migration quality, or can it be dropped for simplicity (and re-added later if needed)?

3. **Script error handling granularity** — The MCP server returns structured JSON with per-package `reason` fields and top-level `error` strings. Should scripts replicate this exact granularity, or is a simpler error model (top-level `error` only) acceptable?

---

## Files Inventory

### New Files (7)

| File | Purpose |
|------|---------|
| `skills/dependency-layers/SKILL.md` | Algorithm instructions for topological layer computation |
| `skills/nuget-package-compat/SKILL.md` | NuGet analysis skill — invocation procedures, I/O schemas |
| `skills/nuget-package-compat/scripts/powershell/Find-RecommendedPackageUpgrades.ps1` | NuGet v3 REST API package upgrade analysis (Windows) |
| `skills/nuget-package-compat/scripts/bash/find-recommended-package-upgrades.sh` | Same (macOS/Linux) |
| `skills/nuget-package-compat/scripts/powershell/Get-MinimalPackageSet.ps1` | Transitive dependency pruning (Windows) |
| `skills/nuget-package-compat/scripts/bash/get-minimal-package-set.sh` | Same (macOS/Linux) |
| `agents/nuget-analysis.agent.md` | Helper subagent with execute permissions for NuGet scripts |

### Modified Files (16)

| File | Change |
|------|--------|
| `agents/assessment.agent.md` | Remove MCP tools, add skill/agent refs, update sections 5b and 7c |
| `agents/sdk-project-conversion.agent.md` | Remove MCP tool, add agent ref, update section 6 |
| `agents/migration-planner.agent.md` | Update `ComputeDependencyLayers` reference text |
| `.mcp.json` | Remove `Swick.Mcp.Fx2dotnet` entry |
| `.github/copilot-instructions.md` | Remove MCP server refs, add skill refs |
| `README.md` | Update tool and MCP server documentation |
| `spec-kit/README.md` | Remove MCP refs |
| `spec-kit/docs/speckit-extension-plan.md` | Update tool references |
| `spec-kit/docs/speckit-deployment-plan.md` | Remove MCP packaging refs |
| `spec-kit/fx-to-dotnet-assess/README.md` | Remove MCP dependency |
| `spec-kit/fx-to-dotnet-assess/extension.yml` | Remove MCP from requires |
| `spec-kit/fx-to-dotnet-assess/commands/assess.md` | Replace MCP tool refs |
| `spec-kit/fx-to-dotnet-plan/commands/plan.md` | Update layer computation ref |
| `spec-kit/fx-to-dotnet-sdk-convert/README.md` | Remove MCP dependency |
| `spec-kit/fx-to-dotnet-sdk-convert/extension.yml` | Remove MCP from requires |
| `spec-kit/fx-to-dotnet-sdk-convert/commands/convert.md` | Replace MCP tool refs |

### Deleted Files (8+)

| File | Reason |
|------|--------|
| `src/fx2dotnet/` (entire tree) | MCP server replaced by skills/scripts |
| `fx2dotnet.slnx` | No buildable projects remain |
| `Directory.Build.props` | Pending evaluation — likely remove |
| `Directory.Build.targets` | Pending evaluation — likely remove |
| `global.json` | Pending evaluation — likely remove |
