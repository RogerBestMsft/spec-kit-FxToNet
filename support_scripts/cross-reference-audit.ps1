#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verify all cross-extension command references resolve to declared commands.
#>

$ErrorActionPreference = 'Stop'

$Extensions = @(
    "fx-to-dotnet"
)

$Root = Split-Path -Parent $PSScriptRoot

function Get-DeclaredCommands {
    param([string]$RootPath)

    $commands = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($ext in $Extensions) {
        $ymlPath = Join-Path (Join-Path $RootPath $ext) "extension.yml"
        if (-not (Test-Path $ymlPath)) { continue }

        $text = Get-Content -Path $ymlPath -Raw -Encoding UTF8
        $matches = [regex]::Matches($text, '^\s+-\s*name:\s*"?([^"\s]+)"?\s*$', 'Multiline')
        foreach ($m in $matches) {
            [void]$commands.Add($m.Groups[1].Value)
        }
    }
    return $commands
}

function Get-AuditErrors {
    param(
        [string]$RootPath,
        [System.Collections.Generic.HashSet[string]]$Declared
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $crossRefPattern = 'speckit\.fx-to-dotnet[\w-]*\.[\w-]+'

    foreach ($ext in $Extensions) {
        $commandsDir = Join-Path (Join-Path $RootPath $ext) "commands"
        if (-not (Test-Path $commandsDir)) { continue }

        foreach ($md in Get-ChildItem -Path $commandsDir -Recurse -Filter "*.md") {
            $text = Get-Content -Path $md.FullName -Raw -Encoding UTF8
            $matches = [regex]::Matches($text, $crossRefPattern)
            foreach ($m in $matches) {
                $ref = $m.Value
                if (-not $Declared.Contains($ref)) {
                    $rel = $md.FullName.Substring($RootPath.Length + 1) -replace '\\', '/'
                    $errors.Add("${rel}: unresolved reference '${ref}'")
                }
            }
        }
    }
    return $errors
}

# --- Main ---
$declared = Get-DeclaredCommands -RootPath $Root

if ($declared.Count -eq 0) {
    Write-Error "ERROR: no commands found in any extension.yml"
    exit 1
}

Write-Host "Found $($declared.Count) declared commands"
$errors = Get-AuditErrors -RootPath $Root -Declared $declared

if ($errors.Count -gt 0) {
    Write-Host "`n$($errors.Count) unresolved cross-references:"
    foreach ($e in $errors) {
        Write-Host "  $e"
    }
    exit 1
}

Write-Host "OK: all cross-extension references resolve"
exit 0
