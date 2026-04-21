#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Remove all spec-kit fx-to-dotnet extensions from the local Spec Kit installation.
.PARAMETER Force
  Skip the confirmation prompt and remove all extensions immediately.
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

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

if (-not $Force) {
    Write-Host "The following extensions will be removed:"
    foreach ($ext in $Extensions) {
        Write-Host "  - $ext"
    }
    $response = Read-Host "`nAre you sure you want to remove all fx-to-dotnet extensions? (y/N)"
    if ($response -notin @('y', 'Y', 'yes', 'Yes')) {
        Write-Host "Aborted."
        return
    }
    Write-Host ""
}

$removeArgs = if ($Force) { @('--force') } else { @() }

foreach ($ext in $Extensions) {
    Write-Host "Removing $ext..."
    specify extension remove $ext @removeArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  $ext was not installed, skipping"
    }
}

Write-Host "`nDone. All fx-to-dotnet extensions removed."
