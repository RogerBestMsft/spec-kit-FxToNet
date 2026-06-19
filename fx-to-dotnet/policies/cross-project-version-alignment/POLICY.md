---
name: cross-project-version-alignment
description: "Cross-project transitive NuGet version alignment analysis. Use when: the solution has multiple projects in a <ProjectReference> dependency chain and you need to detect cases where NuGet's 'highest version wins' resolution will override a lower-layer project's pinned package version at runtime, causing compile-time vs. runtime API mismatches."
---

# Cross-Project Transitive Version Alignment

Detects and resolves NuGet package version conflicts that arise when projects in a `<ProjectReference>` dependency chain pin different versions of the same package. NuGet's "highest version wins" resolution means a library compiled against version X may run against version Y (where Y > X) if a consuming project transitively pulls the higher version.

## When to Use

- **After per-package compatibility analysis** (assess step 7c): To identify packages whose assessed "minimum compatible version" will be overridden by transitive pulls from upstream projects
- **After per-layer package updates** (orchestrator phase 4b): As a validation gate before multitargeting begins, confirming no unresolved version drift exists
- **When the solution has multiple dependency layers**: Single-project solutions or flat (no inter-project references) solutions skip this check

## Problem Statement

Given projects A (Layer 1, leaf) and B (Layer 2, references A):

1. Assessment evaluates A's packages in isolation: "Serilog 2.10.0 supports net10.0? Yes → no upgrade needed"
2. Assessment evaluates B's packages: "Serilog.AspNetCore 9.0.0 supports net10.0? Yes"
3. But Serilog.AspNetCore 9.0.0 transitively depends on Serilog ≥ 4.0.0
4. At build/runtime, NuGet resolves Serilog to 4.x for the entire dependency graph
5. Project A was compiled against Serilog 2.10.0 API but runs against 4.x → potential API breaks

## Algorithm

### Inputs

- **Dependency graph**: Project-to-project references (from `dependency-layers` policy output in `analysis.md`)
- **Package inventory**: Per-project direct `<PackageReference>` entries with versions (from Compatibility Cards in `package-updates.md`)
- **Target framework**: The migration target (e.g., `net10.0`)
- **NuGet feed configuration**: Active feeds for API queries

### Steps

1. **Build the project reference graph** (already available from `dependency-layers` policy output):
   - For each project P, identify its set of `upstream consumers` = all projects that transitively reference P (projects in higher dependency layers that have P in their `<ProjectReference>` chain, directly or indirectly)

2. **Compute effective package closure per project**:
   - For each project P, gather its direct `<PackageReference>` entries with their target versions (use the `Minimum Compatible Version` from Compatibility Cards when an upgrade is needed, otherwise the `Current Version`)
   - Invoke `Get-TransitiveDependencyClosure` with P's package set to determine the full transitive NuGet dependency tree at those versions
   - The result is P's **effective closure**: a flat map of `{packageId → resolvedVersion}` after applying NuGet's "highest version wins" within P's own references

3. **Compute upstream resolution per project**:
   - For each project P, collect the effective closures of ALL upstream consumers of P
   - For each package ID that appears in P's effective closure AND in any upstream consumer's effective closure, determine the **maximum resolved version** across all upstream closures
   - This represents the version that NuGet will actually resolve to when the full solution is built

4. **Detect conflicts**:
   - For each package ID in P's effective closure where the upstream-resolved version is **higher** than P's resolved version:
     - If the version difference is **major version** (breaking change likely): emit a **conflict** (severity: high)
     - If the version difference is **minor version** (new APIs, possible behavioral changes): emit a **warning** (severity: medium)
     - If the version difference is **patch only**: emit an **info** (severity: low) — unlikely to cause issues but worth noting

5. **Compute recommended versions**:
   - For each conflict/warning, the recommended version for project P's package is the **upstream-resolved version** (the version NuGet will actually use at runtime)
   - This ensures the project is compiled against the same API surface it will encounter at runtime
   - Verify the recommended version still supports the target framework (it should, since the upstream project was already assessed as compatible)

6. **Handle Central Package Management (CPM)**:
   - For solutions using `Directory.Packages.props`: conflicts are less likely since versions are centrally pinned
   - However, meta-packages (e.g., `Microsoft.AspNetCore.App`, `Serilog.AspNetCore`) can still pull transitive versions higher than the central pin for packages NOT listed in `Directory.Packages.props`
   - For CPM solutions: only flag conflicts for packages whose centrally-managed version is lower than the transitive resolution from a meta-package dependency

### Output

An **alignment conflicts table** to be recorded in `package-updates.md` under `## Transitive Alignment Conflicts`:

| # | Package ID | Project (lower layer) | Layer | Pinned Version | Resolved Version (upstream) | Upstream Project | Severity | Recommended Version |
|---|------------|----------------------|-------|----------------|-----------------------------|------------------|----------|---------------------|

Field definitions:
- **Pinned Version**: The version P would use based on its own `<PackageReference>` (either current or the assessed minimum compatible version)
- **Resolved Version (upstream)**: The version that NuGet will actually resolve to due to transitive pulls from upstream consumers
- **Upstream Project**: The project(s) whose transitive dependencies pull the higher version
- **Severity**: `high` (major version delta), `medium` (minor version delta), `low` (patch delta)
- **Recommended Version**: The version P should target to avoid compile/runtime mismatch (equals the upstream-resolved version)

If no conflicts are found, emit a single row: `| — | (none) | — | — | — | — | — | — | — |`

## Script Invocation

Detect the OS and use the appropriate script variant:
- **Windows**: `fx-to-dotnet/scripts/powershell/Get-TransitiveDependencyClosure.ps1`
- **macOS/Linux**: `fx-to-dotnet/scripts/bash/get-transitive-dependency-closure.sh`

Scripts accept JSON input via **stdin** and produce JSON output on **stdout**. Diagnostic messages go to stderr.

### Get Transitive Dependency Closure

**PowerShell:**
```powershell
$input | & "fx-to-dotnet/scripts/powershell/Get-TransitiveDependencyClosure.ps1"
```

**Bash:**
```bash
echo "$input" | bash fx-to-dotnet/scripts/bash/get-transitive-dependency-closure.sh
```

**Input JSON:**
```json
{
  "workspaceDirectory": "C:/path/to/solution",
  "nugetConfigPath": null,
  "targetFramework": "net10.0",
  "packages": [
    { "packageId": "Serilog", "version": "2.10.0" },
    { "packageId": "Serilog.Extensions.Logging", "version": "4.1.0" }
  ],
  "includePrerelease": false
}
```

- `workspaceDirectory` — Optional. Used to locate `nuget.config` if `nugetConfigPath` is null.
- `nugetConfigPath` — Optional. Explicit path to a `nuget.config` file.
- `targetFramework` — Required. The TFM to resolve dependency groups against.
- `packages` — Required. The direct package references to resolve transitive closures for.
- `includePrerelease` — Optional, defaults to `false`.

**Output JSON:**
```json
{
  "resolved": {
    "Serilog": "2.10.0",
    "Serilog.Extensions.Logging": "4.1.0",
    "Microsoft.Extensions.Logging": "8.0.0"
  },
  "tree": [
    {
      "packageId": "Serilog",
      "version": "2.10.0",
      "dependencies": []
    },
    {
      "packageId": "Serilog.Extensions.Logging",
      "version": "4.1.0",
      "dependencies": [
        { "packageId": "Microsoft.Extensions.Logging", "versionRange": "[8.0.0, )" },
        { "packageId": "Serilog", "versionRange": "[2.10.0, )" }
      ]
    }
  ],
  "reason": null
}
```

**Output field reference:**
| Field | Meaning |
|-------|---------|
| `resolved` | Flat map of all packages (direct + transitive) with their resolved versions after applying "highest version wins" |
| `tree` | Hierarchical dependency tree showing each package's direct NuGet dependencies with version ranges |
| `reason` | Error message, or `null` on success |

## Error Handling

Scripts always produce valid JSON on stdout, even on failure. Errors are reported via:
- Top-level `reason` field for input validation, configuration errors, or feed connectivity issues
- If a package cannot be found on any configured feed, it is omitted from `resolved` and a warning is emitted to stderr

## NuGet Feed Resolution

Scripts resolve NuGet feeds using the same precedence as `Find-RecommendedPackageUpgrades`:
1. If `nugetConfigPath` is provided and exists, parse that file's `<packageSources>` section
2. Otherwise, search upward from `workspaceDirectory` for the nearest `nuget.config`
3. If no config is found, fall back to `https://api.nuget.org/v3/index.json`

## Version Resolution Rules

The script applies NuGet's standard version resolution:
- **Highest version wins**: When multiple packages depend on the same transitive package with different version ranges, the highest lower-bound wins
- **Dependency group selection**: Choose the dependency group whose TFM is the nearest compatible match for `targetFramework` (prefer exact match → nearest compatible → fallback to `netstandard2.0` → no dependencies)
- **Version range parsing**: Supports NuGet range syntax (`[1.0.0, )`, `[1.0.0, 2.0.0)`, `1.0.0`, etc.)
- **Cycle detection**: If a circular dependency is encountered, break the cycle and emit a stderr warning

## Integration Points

| Consumer | How it uses this policy |
|----------|------------------------|
| `speckit.fx-to-dotnet.assess` (step 7d) | Runs the full algorithm after per-package compatibility analysis; writes `## Transitive Alignment Conflicts` to `package-updates.md` |
| `speckit.fx-to-dotnet.plan` | Reads alignment conflicts; adjusts `toVersion` in chunked update plans to use `Recommended Version` instead of per-package minimum |
| `speckit.fx-to-dotnet.orchestrate` (phase 4b→4c gate) | Re-runs a lightweight version of the check after package updates to validate no residual conflicts before multitargeting |
