<#
.SYNOPSIS
    Finds the minimum NuGet package version supporting modern .NET for each input package,
    with transitive constraint resolution across the input set.
.DESCRIPTION
    Reads JSON from stdin with workspaceDirectory, nugetConfigPath, packages[], and includePrerelease.
    Queries the NuGet v3 REST API to find the minimum version with netstandard/netcoreapp/net5.0+ support.
    After finding per-package minimums, resolves transitive dependency constraints: if package A at its
    recommended version requires package B >= X, and B's recommendation is lower than X, B is bumped.
    This iterates until stable or a max-iteration guard (10) is reached to prevent circular loops.
    Also checks current version's .nupkg for legacy content/ folder and tools/install.ps1.
    Outputs JSON to stdout matching the PackageUpgradeRecommendationResult schema, including a
    constraintBumps[] array documenting any version adjustments due to transitive requirements.
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
            $clearSeen = $false
            $node = $xml.configuration.packageSources
            if ($node) {
                foreach ($child in $node.ChildNodes) {
                    if ($child.LocalName -eq 'clear') {
                        $sources = @()
                        $clearSeen = $true
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

function Get-PackageContentBaseUrl {
    param($ServiceIndex)

    foreach ($resource in $ServiceIndex.resources) {
        $type = $resource.'@type'
        if ($type -is [array]) { $type = $type[0] }
        if ($type -match 'PackageBaseAddress') {
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

    # net5.0+ pattern: netX.Y where X >= 5, must contain a dot after 'net'
    $suffix = $v.Substring(3)
    if ($suffix.Length -gt 0 -and $suffix[0] -match '\d' -and $suffix.Contains('.')) {
        $major = ($suffix -split '\.')[0]
        if ([int]$major -ge 5) { return 'netcore' }
    }

    return $null
}

function Get-AllVersionsFromRegistration {
    param(
        [string]$RegistrationsBaseUrl,
        [string]$PackageId
    )

    $id = $PackageId.ToLowerInvariant()
    $regUrl = "$($RegistrationsBaseUrl.TrimEnd('/'))/$id/index.json"

    try {
        $index = Invoke-RestMethod -Uri $regUrl -UseBasicParsing -ErrorAction Stop
    }
    catch {
        return @()
    }

    $entries = @()
    foreach ($page in $index.items) {
        $pageItems = $page.items
        if (-not $pageItems -and $page.'@id') {
            try {
                $pageData = Invoke-RestMethod -Uri $page.'@id' -UseBasicParsing -ErrorAction Stop
                $pageItems = $pageData.items
            }
            catch { continue }
        }
        if ($pageItems) {
            $entries += $pageItems
        }
    }

    return $entries
}

function Find-MinModernVersion {
    param(
        $Entries,
        [bool]$IncludePrerelease
    )

    foreach ($entry in $Entries) {
        $catalogEntry = $entry.catalogEntry
        if (-not $catalogEntry) { continue }

        $listed = $catalogEntry.listed
        if ($null -ne $listed -and -not $listed) { continue }

        $version = $catalogEntry.version
        if (-not $IncludePrerelease -and $version -match '-') { continue }

        $depGroups = $catalogEntry.dependencyGroups
        if (-not $depGroups) { continue }

        $matchingTfms = @()
        $families = @()

        foreach ($group in $depGroups) {
            $tf = $group.targetFramework
            if (-not $tf) { continue }
            $family = Get-FrameworkFamily -Tfm $tf
            if ($family) {
                $matchingTfms += $tf
                $families += $family
            }
        }

        if ($matchingTfms.Count -gt 0) {
            $uniqueTfms = $matchingTfms | Sort-Object -Unique
            $uniqueFamilies = $families | Sort-Object -Unique
            return @{
                Version = $version
                Supports = @($uniqueTfms)
                SupportFamilies = @($uniqueFamilies)
            }
        }
    }

    return $null
}

function Test-LegacyFlags {
    param(
        [string]$PackageContentBaseUrl,
        [string]$PackageId,
        [string]$Version
    )

    $result = @{ HasLegacyContentFolder = $false; HasInstallScript = $false }

    if (-not $PackageContentBaseUrl) { return $result }

    $id = $PackageId.ToLowerInvariant()
    $ver = $Version.ToLowerInvariant()
    $nupkgUrl = "$($PackageContentBaseUrl.TrimEnd('/'))/$id/$ver/$id.$ver.nupkg"

    $tempFile = [System.IO.Path]::GetTempFileName() + '.nupkg'
    $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())

    try {
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $tempFile -DestinationPath $tempDir -Force -ErrorAction Stop

        $files = Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
            $_.FullName.Substring($tempDir.Length + 1).Replace('\', '/')
        }

        $result.HasLegacyContentFolder = ($files | Where-Object { $_ -match '^content/' }).Count -gt 0
        $result.HasInstallScript = ($files | Where-Object { $_ -ieq 'tools/install.ps1' }).Count -gt 0
    }
    catch {
        Write-Verbose "Legacy flag check failed for ${PackageId}@${Version}: $_"
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    return $result
}

function Compare-Versions {
    param(
        [string]$VersionA,
        [string]$VersionB
    )
    # Strip prerelease for comparison, compare major.minor.patch.revision
    $cleanA = ($VersionA -split '-')[0]
    $cleanB = ($VersionB -split '-')[0]
    try {
        $a = [Version]$cleanA
        $b = [Version]$cleanB
        return $a.CompareTo($b)
    }
    catch {
        return [string]::Compare($VersionA, $VersionB, [StringComparison]::OrdinalIgnoreCase)
    }
}

function Parse-VersionRange {
    <#
    .SYNOPSIS
        Parses a NuGet version range string and returns the lower bound version.
    .DESCRIPTION
        Handles formats: "1.0.0", "[1.0.0, )", "(, 2.0.0]", "[1.0.0]", etc.
        Returns the lower bound version string, or $null if none can be determined.
    #>
    param([string]$Range)

    if (-not $Range) { return $null }

    $r = $Range.Trim()

    # Simple version string (no brackets)
    if ($r -notmatch '[\[\(\]\)]') {
        return $r
    }

    # Remove leading bracket/paren
    $inner = $r.TrimStart('[', '(').TrimEnd(']', ')')
    $parts = $inner -split ','

    if ($parts.Count -ge 1) {
        $lower = $parts[0].Trim()
        if ($lower -ne '' -and $lower -ne ' ') {
            return $lower
        }
    }

    return $null
}

function Get-TransitiveDependencies {
    <#
    .SYNOPSIS
        Extracts the dependency requirements of a specific package version from its catalog entry.
    .DESCRIPTION
        Queries the NuGet registration for a specific version and returns a hashtable of
        { dependencyPackageId (lowered) -> minimumRequiredVersion } for all dependency groups.
    #>
    param(
        [string]$RegistrationsBaseUrl,
        [string]$PackageId,
        [string]$Version
    )

    $deps = @{}
    $id = $PackageId.ToLowerInvariant()
    $entries = Get-AllVersionsFromRegistration -RegistrationsBaseUrl $RegistrationsBaseUrl -PackageId $id

    foreach ($entry in $entries) {
        $catalogEntry = $entry.catalogEntry
        if (-not $catalogEntry) { continue }
        if ($catalogEntry.version -ne $Version) { continue }

        $depGroups = $catalogEntry.dependencyGroups
        if (-not $depGroups) { break }

        foreach ($group in $depGroups) {
            $groupDeps = $group.dependencies
            if (-not $groupDeps) { continue }

            foreach ($dep in $groupDeps) {
                $depId = $dep.id
                if (-not $depId) { continue }
                $depIdLower = $depId.ToLowerInvariant()
                $rangeStr = $dep.range
                if (-not $rangeStr) { continue }

                $minVer = Parse-VersionRange -Range $rangeStr
                if (-not $minVer) { continue }

                # Keep the highest minimum across all dependency groups
                if ($deps.ContainsKey($depIdLower)) {
                    if ((Compare-Versions $minVer $deps[$depIdLower]) -gt 0) {
                        $deps[$depIdLower] = $minVer
                    }
                }
                else {
                    $deps[$depIdLower] = $minVer
                }
            }
        }
        break  # Found the target version, no need to continue
    }

    return $deps
}

function Resolve-TransitiveConstraints {
    <#
    .SYNOPSIS
        Iteratively resolves transitive version constraints across a set of recommended package upgrades.
    .DESCRIPTION
        For each recommended package version, extracts its transitive dependencies. If any dependency
        is also in the input set and the recommended version is lower than what the dependent requires,
        bumps it. Iterates until stable or max iterations reached.
    .PARAMETER RecommendedVersions
        Hashtable of { packageIdLower -> recommendedVersion }
    .PARAMETER Sources
        Array of NuGet source URLs
    .PARAMETER InputPackageIds
        Hashtable of { packageIdLower -> $true } for all packages in the input set
    .PARAMETER MaxIterations
        Maximum constraint resolution iterations (default 10) to prevent infinite loops
    .OUTPUTS
        Hashtable with:
          - Versions: updated { packageIdLower -> resolvedVersion }
          - Bumps: array of { packageId, from, to, requiredBy, requiredVersion }
    #>
    param(
        [hashtable]$RecommendedVersions,
        [array]$Sources,
        [hashtable]$InputPackageIds,
        [int]$MaxIterations = 10
    )

    $versions = @{}
    foreach ($k in $RecommendedVersions.Keys) {
        $versions[$k] = $RecommendedVersions[$k]
    }

    $allBumps = @()
    $iteration = 0

    while ($iteration -lt $MaxIterations) {
        $iteration++
        $changed = $false

        foreach ($pkgId in @($versions.Keys)) {
            $pkgVersion = $versions[$pkgId]

            # Get the registration base URL from first available source
            $regBase = $null
            foreach ($source in $Sources) {
                try {
                    $svcIndex = Get-ServiceIndex -SourceUrl $source
                    $regBase = Get-RegistrationsBaseUrl -ServiceIndex $svcIndex
                    if ($regBase) { break }
                }
                catch { continue }
            }
            if (-not $regBase) { continue }

            # Extract transitive dependencies of this package at its recommended version
            $deps = Get-TransitiveDependencies -RegistrationsBaseUrl $regBase -PackageId $pkgId -Version $pkgVersion

            foreach ($depId in $deps.Keys) {
                $requiredMinVersion = $deps[$depId]

                # Only care about dependencies that are also in our input package set
                if (-not $InputPackageIds.ContainsKey($depId)) { continue }
                if (-not $versions.ContainsKey($depId)) { continue }

                $currentRecommended = $versions[$depId]

                # If the current recommendation is lower than what's required, bump it
                if ((Compare-Versions $currentRecommended $requiredMinVersion) -lt 0) {
                    $allBumps += @{
                        packageId       = $depId
                        from            = $currentRecommended
                        to              = $requiredMinVersion
                        requiredBy      = $pkgId
                        requiredVersion = $requiredMinVersion
                    }
                    $versions[$depId] = $requiredMinVersion
                    $changed = $true
                }
            }
        }

        if (-not $changed) { break }
    }

    if ($iteration -ge $MaxIterations -and $changed) {
        Write-Warning "Transitive constraint resolution did not converge after $MaxIterations iterations. Results may be incomplete."
    }

    return @{
        Versions = $versions
        Bumps    = $allBumps
    }
}

#endregion

# Read input from stdin
$inputJson = $input | Out-String
$request = $inputJson | ConvertFrom-Json

# Validate
if (-not $request.packages -or $request.packages.Count -eq 0) {
    @{ recommendations = @(); reason = 'packages is required and must contain at least one item.' } | ConvertTo-Json -Depth 10
    exit 0
}

$hasEmptyId = $request.packages | Where-Object { -not $_.packageId -or $_.packageId.Trim() -eq '' }
if ($hasEmptyId) {
    @{ recommendations = @(); reason = 'Each package item must include a non-empty packageId.' } | ConvertTo-Json -Depth 10
    exit 0
}

$workspaceDir = if ($request.workspaceDirectory) { $request.workspaceDirectory } else { $PWD.Path }
$nugetConfigPath = $request.nugetConfigPath
$includePrerelease = if ($null -ne $request.includePrerelease) { [bool]$request.includePrerelease } else { $false }

# Resolve NuGet sources
$sources = Resolve-NuGetSources -WorkspaceDirectory $workspaceDir -NuGetConfigPath $nugetConfigPath

$recommendations = @()

foreach ($pkg in $request.packages) {
    $packageId = $pkg.packageId
    $currentVersion = if ($pkg.currentVersion) { $pkg.currentVersion.Trim() } else { '' }

    $minSupport = $null
    $foundFeed = $null
    $hadMetadata = $false

    foreach ($source in $sources) {
        try {
            $svcIndex = Get-ServiceIndex -SourceUrl $source
            $regBase = Get-RegistrationsBaseUrl -ServiceIndex $svcIndex
            if (-not $regBase) { continue }

            $entries = Get-AllVersionsFromRegistration -RegistrationsBaseUrl $regBase -PackageId $packageId
            if ($entries.Count -eq 0) { continue }

            $hadMetadata = $true
            $found = Find-MinModernVersion -Entries $entries -IncludePrerelease $includePrerelease
            if ($found) {
                if (-not $minSupport -or (Compare-Versions $found.Version $minSupport.Version) -lt 0) {
                    $minSupport = $found
                    $foundFeed = $source
                }
            }
        }
        catch {
            Write-Verbose "Source $source failed for ${packageId}: $_"
        }
    }

    # Check legacy flags on current version
    $legacyFlags = @{ HasLegacyContentFolder = $false; HasInstallScript = $false }
    if ($currentVersion -ne '') {
        foreach ($source in $sources) {
            try {
                $svcIndex = Get-ServiceIndex -SourceUrl $source
                $contentBase = Get-PackageContentBaseUrl -ServiceIndex $svcIndex
                if ($contentBase) {
                    $legacyFlags = Test-LegacyFlags -PackageContentBaseUrl $contentBase -PackageId $packageId -Version $currentVersion
                    break
                }
            }
            catch { continue }
        }
    }

    # Determine if upgrade is needed
    $needsUpgrade = $false
    $reason = $null

    if ($minSupport) {
        if ($currentVersion -eq '') {
            $needsUpgrade = $true
            $reason = 'Current version is missing or invalid; review and upgrade to at least the minimum supported version.'
        }
        elseif ((Compare-Versions $currentVersion $minSupport.Version) -lt 0) {
            $needsUpgrade = $true
        }
    }

    if ($needsUpgrade -or $legacyFlags.HasLegacyContentFolder -or $legacyFlags.HasInstallScript) {
        $rec = @{
            packageId = $packageId
            currentVersion = if ($currentVersion -ne '') { $currentVersion } else { $null }
            minimumSupportedVersion = if ($minSupport) { $minSupport.Version } else { $null }
            supports = if ($minSupport) { $minSupport.Supports } else { @() }
            supportFamilies = if ($minSupport) { $minSupport.SupportFamilies } else { @() }
            feed = $foundFeed
            hasLegacyContentFolder = $legacyFlags.HasLegacyContentFolder
            hasInstallScript = $legacyFlags.HasInstallScript
            reason = $reason
        }
        $recommendations += $rec
    }
}

#region Transitive Constraint Resolution

# Build lookup tables for constraint resolution
# RecommendedVersions: packageIdLower -> version to recommend (minimum supported or current if no upgrade needed)
# InputPackageIds: packageIdLower -> $true for all packages in the input set
$recommendedVersions = @{}
$inputPackageIds = @{}

foreach ($pkg in $request.packages) {
    $idLower = $pkg.packageId.ToLowerInvariant()
    $inputPackageIds[$idLower] = $true

    # Find the version we'd end up with: either the recommended minimum or the current version
    $rec = $recommendations | Where-Object { $_.packageId -ieq $pkg.packageId } | Select-Object -First 1
    if ($rec -and $rec.minimumSupportedVersion) {
        $recommendedVersions[$idLower] = $rec.minimumSupportedVersion
    }
    elseif ($pkg.currentVersion) {
        $recommendedVersions[$idLower] = $pkg.currentVersion.Trim()
    }
}

# Only run constraint resolution if we have packages to check
$constraintBumps = @()
if ($recommendedVersions.Count -gt 1) {
    $resolution = Resolve-TransitiveConstraints `
        -RecommendedVersions $recommendedVersions `
        -Sources $sources `
        -InputPackageIds $inputPackageIds `
        -MaxIterations 10

    $constraintBumps = $resolution.Bumps

    # Apply bumps to recommendations
    foreach ($bump in $constraintBumps) {
        $bumpIdLower = $bump.packageId.ToLowerInvariant()

        # Find existing recommendation for this package
        $existingRec = $recommendations | Where-Object { $_.packageId -ieq $bump.packageId } | Select-Object -First 1

        if ($existingRec) {
            # Update the minimumSupportedVersion if the bump target is higher
            if ($existingRec.minimumSupportedVersion) {
                if ((Compare-Versions $bump.to $existingRec.minimumSupportedVersion) -gt 0) {
                    $existingRec.minimumSupportedVersion = $bump.to
                }
            }
            else {
                $existingRec.minimumSupportedVersion = $bump.to
            }
        }
        else {
            # Package wasn't previously in recommendations (it was already compatible at current version)
            # but now needs an upgrade due to a transitive constraint — add it
            $originalPkg = $request.packages | Where-Object { $_.packageId -ieq $bump.packageId } | Select-Object -First 1
            $cv = if ($originalPkg -and $originalPkg.currentVersion) { $originalPkg.currentVersion.Trim() } else { $null }

            $newRec = @{
                packageId = $bump.packageId
                currentVersion = $cv
                minimumSupportedVersion = $bump.to
                supports = @()
                supportFamilies = @()
                feed = $null
                hasLegacyContentFolder = $false
                hasInstallScript = $false
                reason = "Transitive constraint: $($bump.requiredBy) requires >= $($bump.requiredVersion)"
            }
            $recommendations += $newRec
        }
    }
}

#endregion

# Format constraintBumps for output
$constraintBumpsOutput = @()
foreach ($bump in $constraintBumps) {
    $constraintBumpsOutput += @{
        packageId       = $bump.packageId
        from            = $bump.from
        to              = $bump.to
        requiredBy      = $bump.requiredBy
        requiredVersion = $bump.requiredVersion
    }
}

@{ recommendations = $recommendations; constraintBumps = $constraintBumpsOutput; reason = $null } | ConvertTo-Json -Depth 10
