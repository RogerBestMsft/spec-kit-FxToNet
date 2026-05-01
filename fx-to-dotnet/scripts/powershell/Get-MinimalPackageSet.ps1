<#
.SYNOPSIS
    Computes the minimal subset of NuGet packages that must remain as direct PackageReference entries.
.DESCRIPTION
    Reads JSON from stdin with workspaceDirectory, nugetConfigPath, and packages[].
    Queries the NuGet v3 REST API to determine transitive dependencies.
    Packages that are already provided transitively by another package in the set are marked for removal.
    Outputs JSON to stdout matching the MinimalPackageSetResult schema.
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

function Get-PackageDependencies {
    param(
        [string]$RegistrationsBaseUrl,
        [string]$PackageId,
        [string]$Version
    )

    $id = $PackageId.ToLowerInvariant()
    $regUrl = "$($RegistrationsBaseUrl.TrimEnd('/'))/$id/index.json"

    try {
        $index = Invoke-RestMethod -Uri $regUrl -UseBasicParsing -ErrorAction Stop
    }
    catch {
        return @()
    }

    foreach ($page in $index.items) {
        $pageItems = $page.items
        if (-not $pageItems -and $page.'@id') {
            try {
                $pageData = Invoke-RestMethod -Uri $page.'@id' -UseBasicParsing -ErrorAction Stop
                $pageItems = $pageData.items
            }
            catch { continue }
        }
        if (-not $pageItems) { continue }

        foreach ($entry in $pageItems) {
            $catalogEntry = $entry.catalogEntry
            if (-not $catalogEntry) { continue }

            if ($catalogEntry.version -ieq $Version) {
                $depGroups = $catalogEntry.dependencyGroups
                if (-not $depGroups) { return @() }

                $deps = @()
                foreach ($group in $depGroups) {
                    $tf = $group.targetFramework
                    # Include 'any' framework (no TFM specified) and modern TFMs
                    $isModern = (-not $tf) -or (Get-FrameworkFamily -Tfm $tf)
                    if ($isModern -and $group.dependencies) {
                        foreach ($dep in $group.dependencies) {
                            $depId = $dep.id
                            if ($depId) {
                                $deps += $depId
                            }
                        }
                    }
                }

                return $deps | Sort-Object -Unique
            }
        }
    }

    return @()
}

#endregion

# Read input from stdin
$inputJson = $input | Out-String
$request = $inputJson | ConvertFrom-Json

# Validate
if (-not $request.packages -or $request.packages.Count -eq 0) {
    @{ keep = @(); removed = @(); reason = 'packages is required and must contain at least one item.' } | ConvertTo-Json -Depth 10
    exit 0
}

$workspaceDir = if ($request.workspaceDirectory) { $request.workspaceDirectory } else { $PWD.Path }
$nugetConfigPath = $request.nugetConfigPath

# Resolve NuGet sources
$sources = Resolve-NuGetSources -WorkspaceDirectory $workspaceDir -NuGetConfigPath $nugetConfigPath

# Build lookup of input package IDs (case-insensitive)
$inputIds = @{}
foreach ($pkg in $request.packages) {
    $inputIds[$pkg.packageId.ToLowerInvariant()] = $true
}

# For each package, resolve its dependencies and check which input packages it pulls in
$providedBy = @{} # packageId (lower) -> list of provider packageIds

foreach ($pkg in $request.packages) {
    $packageId = $pkg.packageId
    $version = $pkg.currentVersion

    if (-not $version -or $version.Trim() -eq '') { continue }

    $deps = $null
    foreach ($source in $sources) {
        try {
            $svcIndex = Get-ServiceIndex -SourceUrl $source
            $regBase = Get-RegistrationsBaseUrl -ServiceIndex $svcIndex
            if (-not $regBase) { continue }

            $deps = Get-PackageDependencies -RegistrationsBaseUrl $regBase -PackageId $packageId -Version $version
            if ($deps -and $deps.Count -gt 0) { break }
        }
        catch { continue }
    }

    if (-not $deps) { continue }

    foreach ($dep in $deps) {
        $depLower = $dep.ToLowerInvariant()
        if ($inputIds.ContainsKey($depLower)) {
            if (-not $providedBy.ContainsKey($depLower)) {
                $providedBy[$depLower] = @()
            }
            $providedBy[$depLower] += $packageId
        }
    }
}

# Build results
$removed = @()
$redundantIds = @{}

foreach ($depId in $providedBy.Keys) {
    $redundantIds[$depId] = $true
    $providers = $providedBy[$depId] | Sort-Object -Unique
    $originalPkg = $request.packages | Where-Object { $_.packageId.ToLowerInvariant() -eq $depId } | Select-Object -First 1
    $removed += @{
        packageId = $originalPkg.packageId
        currentVersion = $originalPkg.currentVersion
        providedBy = @($providers)
    }
}

$kept = @()
foreach ($pkg in $request.packages) {
    if (-not $redundantIds.ContainsKey($pkg.packageId.ToLowerInvariant())) {
        $kept += @{
            packageId = $pkg.packageId
            currentVersion = $pkg.currentVersion
        }
    }
}

$removed = $removed | Sort-Object { $_.packageId }

@{ keep = $kept; removed = $removed; reason = $null } | ConvertTo-Json -Depth 10
