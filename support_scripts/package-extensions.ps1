#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Package all spec-kit extensions into zip archives under releases/
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$SpecKit  = Split-Path -Parent $PSScriptRoot
# Honor RELEASES_DIR env override (used by CI to pin output inside the workspace).
# Default places releases one level above the workspace root for backwards compatibility.
if ($env:RELEASES_DIR) {
    $Releases = $env:RELEASES_DIR
} else {
    $RepoRoot = Split-Path -Parent $SpecKit
    $Releases = Join-Path $RepoRoot 'releases'
}

# Three release artifacts are produced:
#   1. fx-to-dotnet-<version>.zip                — combined bundle (extension + preset as subfolders)
#   2. fx-to-dotnet-extension-<version>.zip      — extension only (single fx-to-dotnet/ subfolder)
#   3. fx-to-dotnet-sdd-<version>.zip            — preset only (single fx-to-dotnet-sdd/ subfolder)
#
# `specify extension add`/`specify preset add` require the manifest at zip root
# or inside a single top-level subfolder, so the combined bundle is not directly
# installable; the per-artifact zips are.
$BundleId    = 'fx-to-dotnet'
$ExtensionId = 'fx-to-dotnet'
$PresetId    = 'fx-to-dotnet-sdd'
$ExtensionDir = Join-Path $SpecKit $ExtensionId                       # fx-to-dotnet/
$PresetDir    = Join-Path $SpecKit 'presets' $PresetId                # fx-to-dotnet-sdd/

if (-not (Test-Path $Releases)) { New-Item -ItemType Directory -Path $Releases -Force | Out-Null }

function Get-ManifestVersion {
    param([Parameter(Mandatory)][string]$Path)
    $match = Select-String -Path $Path -Pattern '^\s+version:\s*"?([^"\s]+)' | Select-Object -First 1
    if (-not $match) { Write-Error "No version field found in $Path" }
    return $match.Matches.Groups[1].Value
}

$extensionYml = Join-Path $ExtensionDir 'extension.yml'
$presetYml    = Join-Path $PresetDir    'preset.yml'
if (-not (Test-Path $extensionYml)) { Write-Error "$extensionYml not found" }
if (-not (Test-Path $presetYml))    { Write-Error "$presetYml not found" }

$version           = Get-ManifestVersion -Path $extensionYml
$bundleArchive     = Join-Path $Releases "$BundleId-$version.zip"
$extensionArchive  = Join-Path $Releases "$ExtensionId-extension-$version.zip"
$presetArchive     = Join-Path $Releases "$PresetId-$version.zip"

foreach ($a in @($bundleArchive, $extensionArchive, $presetArchive)) {
    if (Test-Path $a) { Remove-Item $a -Force }
}

# Stage into a temporary folder so the zips preserve top-level subfolders
# (Compress-Archive does not support -BasePath rewriting).
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("fx-to-dotnet-bundle-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $stagedExt    = Join-Path $staging $ExtensionId
    $stagedPreset = Join-Path $staging $PresetId
    Copy-Item -Recurse -Path $ExtensionDir -Destination $stagedExt
    Copy-Item -Recurse -Path $PresetDir    -Destination $stagedPreset

    Write-Host "Packaging combined bundle  -> $bundleArchive"
    Compress-Archive -Path @($stagedExt, $stagedPreset) -DestinationPath $bundleArchive -Force

    Write-Host "Packaging extension-only   -> $extensionArchive"
    Compress-Archive -Path $stagedExt    -DestinationPath $extensionArchive -Force

    Write-Host "Packaging preset-only      -> $presetArchive"
    Compress-Archive -Path $stagedPreset -DestinationPath $presetArchive -Force
}
finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}

$count = (Get-ChildItem -Path $Releases -Filter '*.zip').Count
Write-Host "`nDone. $count archive(s) in $Releases"
