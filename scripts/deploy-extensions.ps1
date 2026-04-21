#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Install all spec-kit extensions in dev mode for local development.
#>
[CmdletBinding()]
param()

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
    'fx-to-dotnet-policies'
    'fx-to-dotnet-route-inventory'
)

foreach ($ext in $Extensions) {
    $extDir = Join-Path $SpecKit $ext
    if (-not (Test-Path (Join-Path $extDir 'extension.yml'))) {
        Write-Warning "${ext}: extension.yml not found, skipping"
        continue
    }
    Write-Host "Installing $ext (dev mode)..."
    Write-Host "  Console codepage: $(chcp)" -ForegroundColor DarkGray
    specify extension add --dev $extDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install $ext"
    }
}

$count = (specify extension list | Select-String 'fx-to-dotnet').Count
Write-Host "`nDone. $count fx-to-dotnet extensions installed."
