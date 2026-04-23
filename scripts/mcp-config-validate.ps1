#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate that the canonical .mcp.json snippet in mcp-setup.md is well-formed
    and contains the required MCP server entry with expected properties.
#>

$ErrorActionPreference = 'Stop'

$Extensions = @(
    "fx-to-dotnet"
)

$Root = Split-Path -Parent $PSScriptRoot
$RequiredServer = "Microsoft.GitHubCopilot.Modernization.Mcp"

function Extract-JsonBlock {
    param([string]$Markdown)

    if ($Markdown -match '(?s)```json\s*\r?\n(.*?)\r?\n```') {
        return $Matches[1]
    }
    return $null
}

function Test-McpConfig {
    param(
        [string]$JsonText,
        [string]$SourceFile
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # Parse JSON
    try {
        $config = $JsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $errors.Add("${SourceFile}: invalid JSON in canonical snippet — $($_.Exception.Message)")
        return $errors
    }

    # Check top-level mcpServers key
    if (-not $config.PSObject.Properties['mcpServers']) {
        $errors.Add("${SourceFile}: missing top-level 'mcpServers' key")
        return $errors
    }

    # Check required server entry
    $servers = $config.mcpServers
    if (-not $servers.PSObject.Properties[$RequiredServer]) {
        $errors.Add("${SourceFile}: missing required server '${RequiredServer}' under mcpServers")
        return $errors
    }

    $server = $servers.$RequiredServer

    # Validate type
    if ($server.type -ne 'stdio') {
        $errors.Add("${SourceFile}: server type should be 'stdio', got '$($server.type)'")
    }

    # Validate command
    if ($server.command -ne 'dnx') {
        $errors.Add("${SourceFile}: server command should be 'dnx', got '$($server.command)'")
    }

    # Validate args contains required flags
    $args = @($server.args)
    if ($args -notcontains $RequiredServer) {
        $errors.Add("${SourceFile}: args missing package name '${RequiredServer}'")
    }
    if ($args -notcontains '--yes') {
        $errors.Add("${SourceFile}: args missing '--yes' flag")
    }
    if ($args -notcontains '--prerelease') {
        $errors.Add("${SourceFile}: args missing '--prerelease' flag")
    }

    # Validate tools
    $tools = @($server.tools)
    if ($tools.Count -eq 0) {
        $errors.Add("${SourceFile}: 'tools' array is empty")
    }

    return $errors
}

function Test-CommandReferences {
    param([string]$RootPath)

    $errors = [System.Collections.Generic.List[string]]::new()
    $policyPath = "policies/mcp-setup.md"

    foreach ($ext in $Extensions) {
        foreach ($cmdFile in @("commands/assess/assess.md", "commands/sdk-convert/convert.md")) {
            $fullPath = Join-Path $RootPath $ext $cmdFile
            if (-not (Test-Path $fullPath)) {
                $errors.Add("${ext}/${cmdFile}: file not found")
                continue
            }

            $text = Get-Content -Path $fullPath -Raw -Encoding UTF8

            # Check that the command references the policy doc
            if ($text -notmatch 'policies/mcp-setup\.md') {
                $errors.Add("${ext}/${cmdFile}: does not reference '${policyPath}'")
            }

            # Check that the command references .mcp.json
            if ($text -notmatch '\.mcp\.json') {
                $errors.Add("${ext}/${cmdFile}: does not reference '.mcp.json'")
            }

            # Check that the command has a pre-flight section
            if ($text -notmatch 'MCP Server Pre-flight') {
                $errors.Add("${ext}/${cmdFile}: missing 'MCP Server Pre-flight' section")
            }
        }
    }
    return $errors
}

# --- Main ---
$allErrors = [System.Collections.Generic.List[string]]::new()

# 1. Validate the canonical snippet in each extension's mcp-setup.md
foreach ($ext in $Extensions) {
    $policyFile = Join-Path $Root $ext "policies" "mcp-setup.md"
    $rel = "${ext}/policies/mcp-setup.md"

    if (-not (Test-Path $policyFile)) {
        $allErrors.Add("${rel}: policy file not found")
        continue
    }

    Write-Host "Validating canonical snippet in ${rel}"
    $markdown = Get-Content -Path $policyFile -Raw -Encoding UTF8
    $jsonBlock = Extract-JsonBlock -Markdown $markdown

    if (-not $jsonBlock) {
        $allErrors.Add("${rel}: no JSON code block found")
        continue
    }

    $configErrors = Test-McpConfig -JsonText $jsonBlock -SourceFile $rel
    if ($configErrors -and $configErrors.Count -gt 0) {
        $allErrors.AddRange($configErrors)
    }
}

# 2. Validate consuming commands reference the policy
Write-Host "Validating command pre-flight references"
$refErrors = Test-CommandReferences -RootPath $Root
if ($refErrors -and $refErrors.Count -gt 0) {
    $allErrors.AddRange($refErrors)
}

# --- Summary ---
if ($allErrors.Count -gt 0) {
    Write-Host "`n$($allErrors.Count) MCP config validation error(s):"
    foreach ($e in $allErrors) {
        Write-Host "  $e"
    }
    exit 1
}

Write-Host "OK: MCP config is valid and all consuming commands reference the policy"
exit 0
