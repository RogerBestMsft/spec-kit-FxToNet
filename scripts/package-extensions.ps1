#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Package all spec-kit extensions into zip archives under releases/
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$SpecKit   = Split-Path -Parent $PSScriptRoot
$RepoRoot  = Split-Path -Parent $SpecKit
$Releases  = Join-Path $RepoRoot 'releases'

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

if (-not (Test-Path $Releases)) { New-Item -ItemType Directory -Path $Releases | Out-Null }

foreach ($ext in $Extensions) {
    $extDir = Join-Path $SpecKit $ext
    $ymlPath = Join-Path $extDir 'extension.yml'

    if (-not (Test-Path $ymlPath)) {
        Write-Error "$ymlPath not found"
    }

    $version = (Select-String -Path $ymlPath -Pattern '^\s+version:\s*"?([^"\s]+)' | Select-Object -First 1).Matches.Groups[1].Value
    $archive = Join-Path $Releases "$ext-$version.zip"

    Write-Host "Packaging $ext v$version -> $archive"
    Compress-Archive -Path (Join-Path $extDir '*') -DestinationPath $archive -Force
}

$count = (Get-ChildItem -Path $Releases -Filter '*.zip').Count
Write-Host "`nDone. $count archives in $Releases"
