#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate community catalog JSON entries from extension.yml files.
#>

$ErrorActionPreference = 'Stop'

$Extensions = @(
    "fx-to-dotnet"
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

# --- Main ---
$entries = [System.Collections.Generic.List[object]]::new()

foreach ($extId in $Extensions) {
    $ymlPath = Join-Path $Root $extId "extension.yml"
    if (-not (Test-Path $ymlPath)) {
        Write-Warning "WARNING: $ymlPath not found"
        continue
    }

    $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
    $version     = Get-YamlValue -Text $text -Key "version"
    $name        = Get-YamlValue -Text $text -Key "name"
    $description = Get-YamlValue -Text $text -Key "description"
    $author      = Get-YamlValue -Text $text -Key "author"
    $repo        = Get-YamlValue -Text $text -Key "repository"

    if (-not $author) { $author = "Microsoft" }
    if (-not $repo)   { $repo = "" }

    if (-not $version) {
        Write-Error "ERROR: no version in $ymlPath"
        exit 1
    }

    $entry = [ordered]@{
        id          = $extId
        name        = if ($name) { $name } else { $extId }
        version     = $version
        description = if ($description) { $description } else { "" }
        author      = $author
        url         = "${repo}/releases/download/v${version}/${extId}-${version}.zip"
        repository  = $repo
        tags        = @("dotnet", "migration", "modernization")
        family      = "fx-to-dotnet"
    }
    $entries.Add($entry)
}

$entries | ConvertTo-Json -Depth 5
exit 0
