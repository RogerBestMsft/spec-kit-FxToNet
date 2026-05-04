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

# Single combined release artifact: a zip containing the extension and the
# companion preset as top-level subfolders. Naming follows the extension id.
$BundleId = 'fx-to-dotnet'
$ExtensionDir = Join-Path $SpecKit $BundleId                          # fx-to-dotnet/
$PresetDir    = Join-Path $SpecKit 'presets' 'fx-to-dotnet-sdd'       # fx-to-dotnet-sdd/

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

$version = Get-ManifestVersion -Path $extensionYml
$archive = Join-Path $Releases "$BundleId-$version.zip"

Write-Host "Packaging combined bundle $BundleId v$version -> $archive"
if (Test-Path $archive) { Remove-Item $archive -Force }

# Stage into a temporary folder so the zip preserves the two top-level
# subfolders (Compress-Archive does not support -BasePath rewriting).
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("fx-to-dotnet-bundle-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    Copy-Item -Recurse -Path $ExtensionDir -Destination (Join-Path $staging 'fx-to-dotnet')
    Copy-Item -Recurse -Path $PresetDir    -Destination (Join-Path $staging 'fx-to-dotnet-sdd')
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive -Force
}
finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}

$count = (Get-ChildItem -Path $Releases -Filter '*.zip').Count
Write-Host "`nDone. $count archive(s) in $Releases"
