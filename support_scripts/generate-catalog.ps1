#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate community catalog JSON entries from extension.yml and preset.yml files.
.DESCRIPTION
    Outputs a single JSON object: { extensions: [...], presets: [...] }.
    The extension and the companion preset now ship together inside the
    single fx-to-dotnet-<version>.zip bundle (both extension.yml and
    preset.yml live under the fx-to-dotnet/ subfolder). Both catalog
    entries reference the same combined artifact:
      {repository}/releases/download/v{version}/fx-to-dotnet-{version}.zip
#>

$ErrorActionPreference = 'Stop'

$Extensions = @(
    @{ Id = 'fx-to-dotnet'; ZipBase = 'fx-to-dotnet' }
)

$Presets = @(
    @{ Id = 'fx-to-dotnet-sdd'; ZipBase = 'fx-to-dotnet' }
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
        [string[]]$DefaultTags,
        [string]$ZipBase
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
        url         = "${repo}/releases/download/v${version}/${ZipBase}-${version}.zip"
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

foreach ($ext in $Extensions) {
    $ymlPath = Join-Path $Root $ext.Id 'extension.yml'
    if (-not (Test-Path $ymlPath)) {
        Write-Warning "WARNING: $ymlPath not found"
        continue
    }
    $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
    $entry = Build-Entry -ArtifactId $ext.Id -Text $text -Family 'fx-to-dotnet' `
        -DefaultTags @('dotnet', 'migration', 'modernization') `
        -ZipBase $ext.ZipBase
    if ($entry) { $out.extensions.Add($entry) }
}

foreach ($preset in $Presets) {
    # The preset now ships alongside the extension under fx-to-dotnet/.
    $ymlPath = Join-Path $Root 'fx-to-dotnet' 'preset.yml'
    if (-not (Test-Path $ymlPath)) {
        Write-Warning "WARNING: $ymlPath not found"
        continue
    }
    $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
    $entry = Build-Entry -ArtifactId $preset.Id -Text $text -Family 'fx-to-dotnet' `
        -DefaultTags @('dotnet', 'migration', 'sdd', 'preset') `
        -ZipBase $preset.ZipBase
    if ($entry) { $out.presets.Add($entry) }
}

$out | ConvertTo-Json -Depth 6
exit 0
