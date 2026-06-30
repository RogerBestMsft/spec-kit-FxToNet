#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verify dnx availability and MCP server package resolvability.
    Outputs structured JSON to stdout; diagnostics to stderr.
.DESCRIPTION
    Called by the mcp-preflight command to confirm the MCP server can
    actually start before any migration tool calls are attempted.
    Exit 0 = ready; exit 1 = not ready (see JSON for details).
#>
param()

$ErrorActionPreference = 'Stop'

$result = [ordered]@{
    dnxFound          = $false
    packageResolvable = $false
    error             = $null
}

# 1. Check dnx is on PATH
$dnxCmd = Get-Command dnx -ErrorAction SilentlyContinue
if (-not $dnxCmd) {
    $result.error = "dnx not found on PATH. Install with: dotnet tool install -g Microsoft.DotNet.Tools.Dnx (requires .NET SDK 8.0+)"
    $result | ConvertTo-Json -Compress
    exit 1
}
$result.dnxFound = $true
Write-Host "dnx found at: $($dnxCmd.Source)" -ForegroundColor DarkGray

# 2. Probe package resolution (lightweight — just check if dnx can locate the tool)
$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
try {
    $proc = Start-Process -FilePath $dnxCmd.Source `
        -ArgumentList @(
            "Microsoft.GitHubCopilot.Modernization.Mcp",
            "--help",
            "--prerelease",
            "--source", "https://api.nuget.org/v3/index.json"
        ) `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile

    if ($proc.ExitCode -eq 0) {
        $result.packageResolvable = $true
    }
    else {
        $stderrContent = Get-Content -Path $stderrFile -Raw -ErrorAction SilentlyContinue
        $result.error = "dnx exited with code $($proc.ExitCode). The MCP package may not be resolvable — check network access to https://api.nuget.org/v3/index.json. stderr: $($stderrContent)"
    }
}
catch {
    $result.error = "Failed to invoke dnx: $($_.Exception.Message)"
}
finally {
    Remove-Item -Path $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
}

$result | ConvertTo-Json -Compress
if ($result.packageResolvable) { exit 0 } else { exit 1 }
