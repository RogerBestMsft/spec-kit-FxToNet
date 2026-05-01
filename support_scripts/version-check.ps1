#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verify all spec-kit extensions declare the same version.
#>

$ErrorActionPreference = 'Stop'

$Extensions = @(
    "fx-to-dotnet"
)

$Root = Split-Path -Parent $PSScriptRoot
$versions = @{}
$errors = 0

foreach ($ext in $Extensions) {
    $ymlPath = Join-Path $Root $ext "extension.yml"
    if (-not (Test-Path $ymlPath)) {
        Write-Host "ERROR: $ymlPath not found"
        $errors++
        continue
    }

    $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
    $m = [regex]::Match($text, '^\s+version:\s*"?([^"\s]+)"?\s*$', 'Multiline')
    if (-not $m.Success) {
        Write-Host "ERROR: no version field in $ymlPath"
        $errors++
        continue
    }

    $versions[$ext] = $m.Groups[1].Value
}

if ($errors -gt 0) { exit 1 }

$unique = $versions.Values | Sort-Object -Unique
if (($unique | Measure-Object).Count -ne 1) {
    Write-Host "ERROR: version mismatch across extensions:"
    foreach ($ext in ($versions.Keys | Sort-Object)) {
        Write-Host "  ${ext}: $($versions[$ext])"
    }
    exit 1
}

Write-Host "OK: all $($Extensions.Count) extensions at version $unique"
exit 0
