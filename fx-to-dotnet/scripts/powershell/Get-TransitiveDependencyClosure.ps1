<#
.SYNOPSIS
    Resolves the full transitive NuGet dependency closure for a set of packages.
.DESCRIPTION
    Reads JSON from stdin with workspaceDirectory, nugetConfigPath, targetFramework, packages[], and includePrerelease.
    Queries the NuGet v3 REST API to recursively resolve all transitive dependencies.
    Applies NuGet's "highest version wins" resolution to flatten the dependency tree.
    Outputs JSON to stdout with the resolved flat map and hierarchical tree.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

#region Helpers

function Resolve-NuGetSources {
    param(
        [string]$WorkspaceDirectory,
        [string]$NuGetConfigPath
    )

    $configPath = $null

    if ($NuGetConfigPath -and (Test-Path $NuGetConfigPath)) {
        $configPath = $NuGetConfigPath
    }
    elseif ($WorkspaceDirectory) {
        $dir = $WorkspaceDirectory
        while ($dir) {
            $candidate = Join-Path $dir 'nuget.config'
            if (Test-Path $candidate) {
                $configPath = $candidate
                break
            }
            $parent = Split-Path $dir -Parent
            if ($parent -eq $dir) { break }
            $dir = $parent
        }
    }

    if ($configPath) {
        try {
            [xml]$xml = Get-Content -Path $configPath -Raw
            $sources = @()
            $node = $xml.configuration.packageSources
            if ($node) {
                foreach ($child in $node.ChildNodes) {
                    if ($child.LocalName -eq 'clear') {
                        $sources = @()
                    }
                    elseif ($child.LocalName -eq 'add' -and $child.GetAttribute('value')) {
                        $sources += $child.GetAttribute('value')
                    }
                }
            }
            if ($sources.Count -gt 0) {
                return $sources
            }
        }
        catch {
            Write-Error "Failed to parse nuget.config: $_" 2>$null
        }
    }

    return @('https://api.nuget.org/v3/index.json')
}

function Get-ServiceIndex {
    param([string]$SourceUrl)

    $indexUrl = if ($SourceUrl -match '/index\.json$') { $SourceUrl } else { "$($SourceUrl.TrimEnd('/'))/index.json" }
    $response = Invoke-RestMethod -Uri $indexUrl -UseBasicParsing -ErrorAction Stop
    return $response
}

function Get-RegistrationsBaseUrl {
    param($ServiceIndex)

    foreach ($resource in $ServiceIndex.resources) {
        $type = $resource.'@type'
        if ($type -is [array]) { $type = $type[0] }
        if ($type -match '^RegistrationsBaseUrl') {
            return $resource.'@id'
        }
    }
    return $null
}

function Get-FrameworkFamily {
    param([string]$Tfm)

    $v = $Tfm.ToLowerInvariant()

    if ($v.StartsWith('netstandard')) { return 'netstandard' }
    if (-not $v.StartsWith('net')) { return $null }
    if ($v.StartsWith('netcoreapp')) { return 'netcore' }

    $suffix = $v.Substring(3)
    if ($suffix.Length -gt 0 -and $suffix[0] -match '\d' -and $suffix.Contains('.')) {
        $major = ($suffix -split '\.')[0]
        if ([int]$major -ge 5) { return 'netcore' }
    }

    return $null
}

function Compare-TfmCompatibility {
    param(
        [string]$DependencyGroupTfm,
        [string]$TargetFramework
    )

    # Returns a numeric score for how well a dependency group TFM matches the target.
    # Higher is better. -1 means incompatible.
    $depLower = $DependencyGroupTfm.ToLowerInvariant()
    $targetLower = $TargetFramework.ToLowerInvariant()

    # Exact match
    if ($depLower -eq $targetLower) { return 1000 }

    $depFamily = Get-FrameworkFamily -Tfm $depLower
    $targetFamily = Get-FrameworkFamily -Tfm $targetLower

    # netstandard is compatible with netcore/net5+ targets
    if ($depFamily -eq 'netstandard' -and $targetFamily -eq 'netcore') {
        if ($depLower -match 'netstandard(\d+)\.(\d+)') {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            return 100 + ($major * 10) + $minor
        }
        return 100
    }

    # netcore/net5+ dependency group for netcore/net5+ target
    if ($depFamily -eq 'netcore' -and $targetFamily -eq 'netcore') {
        if ($depLower -match '(\d+)\.(\d+)') {
            $depMajor = [int]$Matches[1]
            $depMinor = [int]$Matches[2]
        }
        else { return 50 }

        if ($targetLower -match '(\d+)\.(\d+)') {
            $targetMajor = [int]$Matches[1]
            $targetMinor = [int]$Matches[2]
        }
        else { return 50 }

        # Dep must be <= target
        if ($depMajor -gt $targetMajor) { return -1 }
        if ($depMajor -eq $targetMajor -and $depMinor -gt $targetMinor) { return -1 }

        return 500 + ($depMajor * 10) + $depMinor
    }

    return -1
}

function Select-BestDependencyGroup {
    param(
        $DependencyGroups,
        [string]$TargetFramework
    )

    $bestScore = -1
    $bestGroup = $null

    foreach ($group in $DependencyGroups) {
        $tf = $group.targetFramework
        if (-not $tf) {
            # Fallback group (no TFM restriction) — use if nothing better
            if ($bestScore -lt 0) {
                $bestScore = 0
                $bestGroup = $group
            }
            continue
        }

        $score = Compare-TfmCompatibility -DependencyGroupTfm $tf -TargetFramework $TargetFramework
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestGroup = $group
        }
    }

    return $bestGroup
}

function Parse-VersionRange {
    param([string]$Range)

    # Returns the minimum version from a NuGet version range
    # Supported formats: "1.0.0", "[1.0.0, )", "[1.0.0, 2.0.0)", "(1.0.0, )"
    if (-not $Range) { return $null }

    $r = $Range.Trim()

    # Simple version string (no brackets)
    if ($r -notmatch '[\[\(]') {
        return $r
    }

    # Extract lower bound from range notation
    $r = $r.TrimStart('[', '(').TrimEnd(']', ')')
    $parts = $r -split ','
    $lower = $parts[0].Trim()

    if ($lower -and $lower -ne '') {
        return $lower
    }

    return $null
}

function Compare-Versions {
    param(
        [string]$Version1,
        [string]$Version2
    )

    # Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
    # Strip pre-release suffixes for comparison
    $v1Clean = ($Version1 -split '-')[0]
    $v2Clean = ($Version2 -split '-')[0]

    try {
        $sv1 = [System.Version]::new($v1Clean)
        $sv2 = [System.Version]::new($v2Clean)
        return $sv1.CompareTo($sv2)
    }
    catch {
        # Fallback: string comparison
        return [string]::Compare($v1Clean, $v2Clean, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

#endregion

#region Main Logic

# Read JSON from stdin
$inputJson = @($input) -join "`n"
if (-not $inputJson) {
    Write-Output '{"resolved":{},"tree":[],"reason":"No input provided on stdin."}'
    exit 0
}

try {
    $request = $inputJson | ConvertFrom-Json
}
catch {
    Write-Output '{"resolved":{},"tree":[],"reason":"Invalid JSON input."}'
    exit 0
}

# Validate input
if (-not $request.packages -or $request.packages.Count -eq 0) {
    Write-Output '{"resolved":{},"tree":[],"reason":"packages is required and must contain at least one item."}'
    exit 0
}

$targetFramework = $request.targetFramework
if (-not $targetFramework) {
    Write-Output '{"resolved":{},"tree":[],"reason":"targetFramework is required."}'
    exit 0
}

$includePrerelease = if ($request.includePrerelease) { $true } else { $false }

# Resolve NuGet sources
$sources = Resolve-NuGetSources -WorkspaceDirectory $request.workspaceDirectory -NuGetConfigPath $request.nugetConfigPath

# Get service index from first available source
$serviceIndex = $null
$registrationsBaseUrl = $null
foreach ($source in $sources) {
    try {
        $serviceIndex = Get-ServiceIndex -SourceUrl $source
        $registrationsBaseUrl = Get-RegistrationsBaseUrl -ServiceIndex $serviceIndex
        if ($registrationsBaseUrl) { break }
    }
    catch {
        Write-Error "Failed to connect to NuGet source ${source}: $_" 2>$null
        continue
    }
}

if (-not $registrationsBaseUrl) {
    Write-Output '{"resolved":{},"tree":[],"reason":"Could not connect to any NuGet source or find RegistrationsBaseUrl."}'
    exit 0
}

# Cache for resolved package metadata: key = "packageId|version", value = dependencies array
$script:metadataCache = @{}

# Track packages being resolved (cycle detection)
$script:resolving = @{}

function Get-PackageDependencies {
    param(
        [string]$PackageId,
        [string]$Version
    )

    $cacheKey = "$($PackageId.ToLowerInvariant())|$Version"

    if ($script:metadataCache.ContainsKey($cacheKey)) {
        return $script:metadataCache[$cacheKey]
    }

    # Cycle detection
    if ($script:resolving.ContainsKey($cacheKey)) {
        Write-Error "Circular dependency detected: $PackageId $Version" 2>$null
        return @()
    }
    $script:resolving[$cacheKey] = $true

    $id = $PackageId.ToLowerInvariant()
    $regUrl = "$($registrationsBaseUrl.TrimEnd('/'))/$id/$($Version.ToLowerInvariant()).json"

    $dependencies = @()

    try {
        $leaf = Invoke-RestMethod -Uri $regUrl -UseBasicParsing -ErrorAction Stop
        $catalogEntry = $leaf.catalogEntry
        if (-not $catalogEntry) { $catalogEntry = $leaf }

        $depGroups = $catalogEntry.dependencyGroups
        if ($depGroups) {
            $bestGroup = Select-BestDependencyGroup -DependencyGroups $depGroups -TargetFramework $targetFramework
            if ($bestGroup -and $bestGroup.dependencies) {
                foreach ($dep in $bestGroup.dependencies) {
                    $depId = $dep.id
                    if (-not $depId) { continue }
                    $depRange = $dep.range
                    if (-not $depRange) { $depRange = $dep.version }
                    $dependencies += @{
                        packageId    = $depId
                        versionRange = $depRange
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get metadata for ${PackageId} ${Version}: $_" 2>$null
    }

    $script:metadataCache[$cacheKey] = $dependencies
    $script:resolving.Remove($cacheKey)

    return $dependencies
}

function Resolve-TransitiveClosure {
    param(
        [array]$DirectPackages
    )

    # resolved: packageId (lowercase) → highest resolved version
    $resolved = @{}
    # tree: list of { packageId, version, dependencies[] }
    $tree = @()
    # queue of packages to process
    $queue = [System.Collections.Queue]::new()

    foreach ($pkg in $DirectPackages) {
        $id = $pkg.packageId
        $ver = $pkg.version
        if (-not $id -or -not $ver) { continue }

        $idLower = $id.ToLowerInvariant()
        $resolved[$idLower] = $ver
        $queue.Enqueue(@{ packageId = $id; version = $ver })
    }

    $processed = @{}

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $pkgId = $current.packageId
        $pkgVer = $current.version
        $processKey = "$($pkgId.ToLowerInvariant())|$pkgVer"

        if ($processed.ContainsKey($processKey)) { continue }
        $processed[$processKey] = $true

        $deps = Get-PackageDependencies -PackageId $pkgId -Version $pkgVer

        $treeEntry = @{
            packageId    = $pkgId
            version      = $pkgVer
            dependencies = @()
        }

        foreach ($dep in $deps) {
            $depId = $dep.packageId
            $depRange = $dep.versionRange
            $depMinVersion = Parse-VersionRange -Range $depRange

            if (-not $depMinVersion) { continue }

            $treeEntry.dependencies += @{
                packageId    = $depId
                versionRange = if ($depRange) { $depRange } else { $depMinVersion }
            }

            $depIdLower = $depId.ToLowerInvariant()

            # Apply "highest version wins"
            if ($resolved.ContainsKey($depIdLower)) {
                $existingVersion = $resolved[$depIdLower]
                $cmp = Compare-Versions -Version1 $depMinVersion -Version2 $existingVersion
                if ($cmp -gt 0) {
                    # New version is higher — update and re-queue
                    $resolved[$depIdLower] = $depMinVersion
                    $queue.Enqueue(@{ packageId = $depId; version = $depMinVersion })
                }
                # If existing is already higher or equal, no action needed
            }
            else {
                $resolved[$depIdLower] = $depMinVersion
                $queue.Enqueue(@{ packageId = $depId; version = $depMinVersion })
            }
        }

        $tree += $treeEntry
    }

    return @{
        resolved = $resolved
        tree     = $tree
    }
}

# Run resolution
$result = Resolve-TransitiveClosure -DirectPackages $request.packages

# Build output JSON
$output = @{
    resolved = $result.resolved
    tree     = $result.tree
    reason   = $null
}

$output | ConvertTo-Json -Depth 10 -Compress | Write-Output

#endregion
