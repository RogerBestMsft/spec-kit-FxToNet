#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate that the canonical .mcp.json snippet in mcp-setup/POLICY.md is well-formed
    and contains the required MCP server entry with expected properties.
#>

$ErrorActionPreference = 'Stop'

$Extensions = @(
    "fx-to-dotnet"
)

$Root = Split-Path -Parent $PSScriptRoot
$RequiredServer = "Microsoft.GitHubCopilot.Modernization.Mcp"

function Extract-JsonBlocks {
    param([string]$Markdown)

    $blocks = [System.Collections.Generic.List[string]]::new()
    $regex = [regex]::new('(?s)```json\s*\r?\n(.*?)\r?\n```')
    foreach ($m in $regex.Matches($Markdown)) {
        $blocks.Add($m.Groups[1].Value)
    }
    return ,$blocks
}

function Test-McpConfig {
    param(
        [string]$JsonText,
        [string]$SourceFile,
        [string]$TopKey  # 'mcpServers' or 'servers'
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

    # Check top-level container key (varies by host)
    if (-not $config.PSObject.Properties[$TopKey]) {
        $errors.Add("${SourceFile}: missing top-level '${TopKey}' key")
        return $errors
    }

    # Check required server entry
    $servers = $config.$TopKey
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
    if ($args -notcontains '--source') {
        $errors.Add("${SourceFile}: args missing '--source' flag")
    }
    if ($args -notcontains 'https://api.nuget.org/v3/index.json') {
        $errors.Add("${SourceFile}: args missing NuGet source URL 'https://api.nuget.org/v3/index.json'")
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
    $policyPath = "policies/mcp-setup/POLICY.md"

    foreach ($ext in $Extensions) {
        foreach ($cmdFile in @("commands/assess/assess.md", "commands/sdk-convert/convert.md")) {
            $fullPath = Join-Path $RootPath $ext $cmdFile
            if (-not (Test-Path $fullPath)) {
                $errors.Add("${ext}/${cmdFile}: file not found")
                continue
            }

            $text = Get-Content -Path $fullPath -Raw -Encoding UTF8

            # Check that the command references the policy doc OR delegates to mcp-preflight
            $refsPolicy = $text -match 'policies/mcp-setup/POLICY\.md'
            $refsPreflight = $text -match 'mcp-preflight'
            if (-not $refsPolicy -and -not $refsPreflight) {
                $errors.Add("${ext}/${cmdFile}: does not reference '${policyPath}' or delegate to mcp-preflight")
            }

            # Check that the command has a pre-flight section
            if ($text -notmatch 'MCP Server Pre-flight') {
                $errors.Add("${ext}/${cmdFile}: missing 'MCP Server Pre-flight' section")
            }
        }
    }
    return ,$errors
}

# --- Main ---
$allErrors = [System.Collections.Generic.List[string]]::new()

# 1. Validate the canonical snippet in each extension's mcp-setup/POLICY.md
foreach ($ext in $Extensions) {
    $policyFile = Join-Path $Root $ext "policies" "mcp-setup" "POLICY.md"
    $rel = "${ext}/policies/mcp-setup/POLICY.md"

    if (-not (Test-Path $policyFile)) {
        $allErrors.Add("${rel}: policy file not found")
        continue
    }

    Write-Host "Validating canonical snippets in ${rel}"
    $markdown = Get-Content -Path $policyFile -Raw -Encoding UTF8
    $jsonBlocks = Extract-JsonBlocks -Markdown $markdown

    if (-not $jsonBlocks -or $jsonBlocks.Count -eq 0) {
        $allErrors.Add("${rel}: no JSON code block found")
        continue
    }

    $foundMcpServers = $false
    $foundServers = $false
    foreach ($block in $jsonBlocks) {
        # Determine which top-level key this block uses by parsing once.
        try {
            $parsed = $block | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $allErrors.Add("${rel}: invalid JSON in canonical snippet — $($_.Exception.Message)")
            continue
        }
        $topKey = $null
        if ($parsed.PSObject.Properties['mcpServers']) { $topKey = 'mcpServers' }
        elseif ($parsed.PSObject.Properties['servers']) { $topKey = 'servers' }
        else {
            $allErrors.Add("${rel}: JSON block missing both 'mcpServers' and 'servers' top-level keys")
            continue
        }

        $configErrors = Test-McpConfig -JsonText $block -SourceFile $rel -TopKey $topKey
        if ($configErrors -and $configErrors.Count -gt 0) {
            $allErrors.AddRange($configErrors)
        }
        else {
            if ($topKey -eq 'mcpServers') { $foundMcpServers = $true }
            elseif ($topKey -eq 'servers') { $foundServers = $true }
        }
    }

    if (-not $foundMcpServers) {
        $allErrors.Add("${rel}: missing valid 'mcpServers' canonical snippet (required for VS / Cursor / Windsurf / JetBrains / generic hosts)")
    }
    if (-not $foundServers) {
        $allErrors.Add("${rel}: missing valid 'servers' canonical snippet (required for VS Code host)")
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
