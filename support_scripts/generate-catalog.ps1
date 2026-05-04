#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate community catalog JSON entries from extension.yml and preset.yml files.
.DESCRIPTION
    Outputs a single JSON object: { extensions: [...], presets: [...] }.
    Both entries reference the same combined release artifact:
      {repository}/releases/download/v{version}/fx-to-dotnet-{version}.zip
#>

$ErrorActionPreference = 'Stop'

$BundleId = 'fx-to-dotnet'  # name of the single combined release zip

$Extensions = @(
    'fx-to-dotnet'
)

$Presets = @(
    'fx-to-dotnet-sdd'
)

$Root = Split-Path -Parent $PSScriptRoot

function Get-YamlValue {
    param(
        [string]$Text,
        [string]$Key
    )
    $m = [regex]::Match($Text, "^\s+${Key}:\s*`"?([^`"\n]+?)`"?\s*$", 'Multiline')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Build-Entry {
    param(
        [string]$ArtifactId,
        [string]$Text,
        [string]$Family,
        [string[]]$DefaultTags
    )
    $version = Get-YamlValue -Text $Text -Key 'version'
    if (-not $version) {
        Write-Error "No version for $ArtifactId"
        return $null
    }
    $repo = Get-YamlValue -Text $Text -Key 'repository'
    if (-not $repo) { $repo = '' }
    $author = Get-YamlValue -Text $Text -Key 'author'
    if (-not $author) { $author = 'Microsoft' }
    $name = Get-YamlValue -Text $Text -Key 'name'
    if (-not $name) { $name = $ArtifactId }
    $description = Get-YamlValue -Text $Text -Key 'description'
    if (-not $description) { $description = '' }

    return [ordered]@{
        id          = $ArtifactId
        name        = $name
        version     = $version
        description = $description
        author      = $author
        url         = "${repo}/releases/download/v${version}/${BundleId}-${version}.zip"
        repository  = $repo
        tags        = $DefaultTags
        family      = $Family
        verified    = $false
    }
}

$out = [ordered]@{
    extensions = [System.Collections.Generic.List[object]]::new()
    presets    = [System.Collections.Generic.List[object]]::new()
}

foreach ($extId in $Extensions) {
    $ymlPath = Join-Path $Root $extId 'extension.yml'
    if (-not (Test-Path $ymlPath)) {
        Write-Warning "WARNING: $ymlPath not found"
        continue
    }
    $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
    $entry = Build-Entry -ArtifactId $extId -Text $text -Family 'fx-to-dotnet' `
        -DefaultTags @('dotnet', 'migration', 'modernization')
    if ($entry) { $out.extensions.Add($entry) }
}

foreach ($presetId in $Presets) {
    $ymlPath = Join-Path $Root 'presets' $presetId 'preset.yml'
    if (-not (Test-Path $ymlPath)) {
        Write-Warning "WARNING: $ymlPath not found"
        continue
    }
    $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
    $entry = Build-Entry -ArtifactId $presetId -Text $text -Family 'fx-to-dotnet' `
        -DefaultTags @('dotnet', 'migration', 'sdd', 'preset')
    if ($entry) { $out.presets.Add($entry) }
}

$out | ConvertTo-Json -Depth 6
exit 0
