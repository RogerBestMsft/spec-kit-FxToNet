---
name: nuget-package-compat
description: "NuGet package compatibility analysis for .NET Framework to modern .NET migration. Use when: evaluating NuGet package upgrade recommendations, finding minimum modern .NET compatible versions, pruning transitive package references, computing minimal PackageReference sets during SDK-style project conversion, or checking for legacy NuGet package flags."
---

# NuGet Package Compatibility Analysis

Scripts that query the NuGet v3 REST API to analyze package compatibility for .NET migration scenarios. Two operations are provided:

1. **Find Recommended Package Upgrades** — For each package, find the minimum version supporting modern .NET (netstandard, netcoreapp, net5.0+). Also checks for legacy package flags.
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
$input | & "skills/nuget-package-compat/scripts/powershell/Find-RecommendedPackageUpgrades.ps1"
```

**Bash:**
```bash
echo "$input" | bash skills/nuget-package-compat/scripts/bash/find-recommended-package-upgrades.sh
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
$input | & "skills/nuget-package-compat/scripts/powershell/Get-MinimalPackageSet.ps1"
```

**Bash:**
```bash
echo "$input" | bash skills/nuget-package-compat/scripts/bash/get-minimal-package-set.sh
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

## Framework Family Classification

A TFM is classified as modern .NET compatible if it belongs to one of these families:

| Pattern | Family |
|---------|--------|
| `netstandardX.Y` | `netstandard` |
| `netcoreappX.Y` | `netcore` |
| `netX.Y` (where X ≥ 5) | `netcore` |

TFMs like `net45`, `net472` (no dot, pre-5.0) are **not** modern .NET and are excluded.
