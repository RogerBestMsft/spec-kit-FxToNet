#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Package the fx-to-dotnet extension (which now also ships the
  fx-to-dotnet-sdd preset alongside extension.yml) into a single zip
  archive under releases/.
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

# A single release artifact is produced:
#   fx-to-dotnet.zip — extension + companion preset together,
#                      with both extension.yml and preset.yml inside the
#                      single fx-to-dotnet/ subfolder.
#
# The archive name is unversioned; the release tag (e.g. v1.0.0) provides
# the version namespace via the GitHub Releases download URL.
#
# `specify extension add` and `specify preset add` both accept a manifest
# inside a single top-level subfolder, so this layout is installable as
# either an extension or a preset from the same zip.
$BundleId    = 'fx-to-dotnet'
$ExtensionId = 'fx-to-dotnet'
$ExtensionDir = Join-Path $SpecKit $ExtensionId                       # fx-to-dotnet/

if (-not (Test-Path $Releases)) { New-Item -ItemType Directory -Path $Releases -Force | Out-Null }

function Get-ManifestVersion {
    param([Parameter(Mandatory)][string]$Path)
    $match = Select-String -Path $Path -Pattern '^\s+version:\s*"?([^"\s]+)' | Select-Object -First 1
    if (-not $match) { Write-Error "No version field found in $Path" }
    return $match.Matches.Groups[1].Value
}

$extensionYml = Join-Path $ExtensionDir 'extension.yml'
$presetYml    = Join-Path $ExtensionDir 'preset.yml'
if (-not (Test-Path $extensionYml)) { Write-Error "$extensionYml not found" }
if (-not (Test-Path $presetYml))    { Write-Error "$presetYml not found" }

$version       = Get-ManifestVersion -Path $extensionYml
Write-Host "Manifest version: $version"
$bundleArchive = Join-Path $Releases "$BundleId.zip"

if (Test-Path $bundleArchive) { Remove-Item $bundleArchive -Force }

# Stage into a temporary folder so the zip preserves the top-level subfolder
# (Compress-Archive does not support -BasePath rewriting).
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("fx-to-dotnet-bundle-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $stagedExt = Join-Path $staging $ExtensionId
    Copy-Item -Recurse -Path $ExtensionDir -Destination $stagedExt

    Write-Host "Packaging combined bundle  -> $bundleArchive"
    Compress-Archive -Path $stagedExt -DestinationPath $bundleArchive -Force
}
finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}

$count = (Get-ChildItem -Path $Releases -Filter '*.zip').Count
Write-Host "`nDone. $count archive(s) in $Releases"
