---
name: nuget-package-compat
description: "NuGet package compatibility analysis for .NET Framework to modern .NET migration. Use when: evaluating NuGet package upgrade recommendations, finding minimum modern .NET compatible versions, pruning transitive package references, computing minimal PackageReference sets during SDK-style project conversion, or checking for legacy NuGet package flags."
scope: core
applies-to: [assess, plan]
---

# NuGet Package Compatibility Analysis

Scripts that query the NuGet v3 REST API to analyze package compatibility for .NET migration scenarios. Two operations are provided:

1. **Find Recommended Package Upgrades** — For each package, find the minimum version supporting modern .NET (netstandard, netcoreapp, net5.0+). Also checks for legacy package flags. After finding per-package minimums, **resolves transitive dependency constraints** across the input set to ensure recommended versions are mutually compatible.
2. **Get Minimal Package Set** — Given a set of packages, prune those that are transitively provided by other packages in the set.

## When to Use

- **Assessment phase**: Determine which packages need upgrades for .NET compatibility
- **SDK-style conversion**: Prune redundant PackageReference entries after converting to SDK-style project format

## Script Invocation

Detect the OS and use the appropriate script variant:
- **Windows**: PowerShell scripts in `scripts/powershell/`
- **macOS/Linux**: Bash scripts in `scripts/bash/`

All scripts accept JSON input via **stdin** and produce JSON output on **stdout**. Diagnostic messages go to stderr.

### Find Recommended Package Upgrades

**PowerShell:**
```powershell
$input | & "fx-to-dotnet/scripts/powershell/Find-RecommendedPackageUpgrades.ps1"
```

**Bash:**
```bash
echo "$input" | bash fx-to-dotnet/scripts/bash/find-recommended-package-upgrades.sh
```

**Input JSON:**
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

- `workspaceDirectory` — Optional. Used to locate `nuget.config` if `nugetConfigPath` is null.
- `nugetConfigPath` — Optional. Explicit path to a `nuget.config` file.
- `packages` — Required. At least one entry with `packageId` and `currentVersion`.
- `includePrerelease` — Optional, defaults to `false`.

**Output JSON:**
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

A package appears in `recommendations` only if it needs an upgrade or has legacy flags. Packages already compatible at their current version and without legacy flags are omitted.

**Output field reference:**
| Field | Meaning |
|-------|---------|
| `minimumSupportedVersion` | Lowest version with netstandard/netcoreapp/net5.0+ support. `null` if no compatible version found. |
| `supports` | TFM short names from the minimum compatible version's dependency groups |
| `supportFamilies` | `"netstandard"` and/or `"netcore"` |
| `feed` | The NuGet source URL where the compatible version was found |
| `hasLegacyContentFolder` | `true` if current version's .nupkg contains a `content/` folder (legacy content deployment, incompatible with PackageReference) |
| `hasInstallScript` | `true` if current version's .nupkg contains `tools/install.ps1` (silently ignored under PackageReference) |
| `reason` | Per-package error/info message, or `null` |

### Get Minimal Package Set

**PowerShell:**
```powershell
$input | & "fx-to-dotnet/scripts/powershell/Get-MinimalPackageSet.ps1"
```

**Bash:**
```bash
echo "$input" | bash fx-to-dotnet/scripts/bash/get-minimal-package-set.sh
```

**Input JSON:**
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

**Output JSON:**
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

**Output field reference:**
| Field | Meaning |
|-------|---------|
| `keep` | Packages that must remain as direct PackageReference entries |
| `removed` | Packages that are transitively provided by other packages in the input set |
| `removed[].providedBy` | Which input packages pull in this package as a transitive dependency |
| `reason` | Top-level error message, or `null` on success |

## Error Handling

Scripts always produce valid JSON on stdout, even on failure. Errors are reported via:
- Top-level `reason` field for input validation or configuration errors
- Per-package `reason` field for individual package lookup failures

## NuGet Feed Resolution

Scripts resolve NuGet feeds in this order:
1. If `nugetConfigPath` is provided and exists, parse that file's `<packageSources>` section
2. Otherwise, search upward from `workspaceDirectory` for the nearest `nuget.config`
3. If no config is found, fall back to `https://api.nuget.org/v3/index.json`

## Transitive Constraint Resolution

After finding per-package minimum compatible versions, the script performs **cross-package transitive constraint resolution** to ensure the recommended versions are mutually compatible.

### Algorithm

1. Build a map of `{ packageId -> recommendedVersion }` for all input packages (using the recommended minimum or current version if no upgrade is needed).
2. For each package in the map, query the NuGet catalog entry for its recommended version and extract the `dependencyGroups[].dependencies[]` — specifically the version range lower bounds.
3. For each dependency that is also in the input package set, check whether the current recommendation satisfies the required minimum. If not, bump the recommendation to the required minimum.
4. Repeat steps 2–3 until no further bumps occur or **10 iterations** are reached (circular constraint guard).
5. If the guard is triggered, emit a warning to stderr and return partial results.

### Example

Given input packages:
- `Microsoft.Data.SqlClient` at 5.1.0 → minimum modern version: 6.0.1
- `Microsoft.EntityFramework.SqlServer` at 6.2.0 → minimum modern version: 6.5.2

EF.SqlServer 6.5.2 declares a dependency on `Microsoft.Data.SqlClient >= 6.1.4`. Since the independent recommendation for SqlClient is 6.0.1 (< 6.1.4), the constraint resolver bumps SqlClient to 6.1.4.

Output includes:
```json
"constraintBumps": [
  {
    "packageId": "microsoft.data.sqlclient",
    "from": "6.0.1",
    "to": "6.1.4",
    "requiredBy": "microsoft.entityframework.sqlserver",
    "requiredVersion": "6.1.4"
  }
]
```

### Circular Constraint Guard

The resolution loop is capped at 10 iterations. This prevents infinite loops in the rare case where package A requires B >= X and B requires A >= Y, with both bumps triggering further bumps. If the guard is triggered, the script:
- Emits a warning to stderr
- Returns the best-effort result with whatever bumps were applied
- Sets the top-level `reason` to `null` (the warning is diagnostic, not fatal)

Downstream consumers (e.g., `speckit.fx-to-dotnet.assess`) should surface the warning if `constraintBumps` is non-empty after max iterations.

## Framework Family Classification

A TFM is classified as modern .NET compatible if it belongs to one of these families:

| Pattern | Family |
|---------|--------|
| `netstandardX.Y` | `netstandard` |
| `netcoreappX.Y` | `netcore` |
| `netX.Y` (where X ≥ 5) | `netcore` |

TFMs like `net45`, `net472` (no dot, pre-5.0) are **not** modern .NET and are excluded.
