#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Bump the extension version in all spec-kit extension.yml files.
  Only the extension:version field is updated; schema_version and
  requires:speckit_version are left unchanged.
.EXAMPLE
  scripts/bump-version.ps1 -Version 0.1.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

$SpecKit = Split-Path -Parent $PSScriptRoot

$Extensions = @(
    'fx-to-dotnet'
    'fx-to-dotnet-assess'
    'fx-to-dotnet-plan'
    'fx-to-dotnet-sdk-convert'
    'fx-to-dotnet-build-fix'
    'fx-to-dotnet-package-compat'
    'fx-to-dotnet-multitarget'
    'fx-to-dotnet-web-migrate'
    'fx-to-dotnet-detect-project'
    'fx-to-dotnet-route-inventory'
    'fx-to-dotnet-policies'
)

foreach ($ext in $Extensions) {
    $yml = Join-Path $SpecKit $ext 'extension.yml'
    if (-not (Test-Path $yml)) {
        Write-Warning "$yml not found"
        continue
    }
    $content = Get-Content $yml -Raw
    # Bump extension version (indented "version:" under extension:)
    $content = $content -replace '(?m)(^\s+version:\s*)"?[^"\s]+"?', "`${1}`"$Version`""
    Set-Content -Path $yml -Value $content -NoNewline
    Write-Host "  $ext -> $Version"
}

Write-Host "Bumped all extensions to $Version"
