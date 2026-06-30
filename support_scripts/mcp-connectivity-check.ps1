#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Developer convenience wrapper — delegates to the deployed connectivity probe script.
#>
$Root = Split-Path -Parent $PSScriptRoot
$Script = Join-Path $Root "fx-to-dotnet" "scripts" "powershell" "Mcp-ConnectivityCheck.ps1"
& $Script @args
exit $LASTEXITCODE
