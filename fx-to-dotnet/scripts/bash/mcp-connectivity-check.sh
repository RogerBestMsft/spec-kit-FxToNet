#!/usr/bin/env bash
# Verify dnx availability and MCP server package resolvability.
# Outputs structured JSON to stdout; diagnostics to stderr.
#
# Called by the mcp-preflight command to confirm the MCP server can
# actually start before any migration tool calls are attempted.
# Exit 0 = ready; exit 1 = not ready (see JSON for details).
set -euo pipefail

PACKAGE="Microsoft.GitHubCopilot.Modernization.Mcp"
FEED="https://api.nuget.org/v3/index.json"

# 1. Check dnx is on PATH
if ! command -v dnx &>/dev/null; then
    printf '{"dnxFound":false,"packageResolvable":false,"error":"dnx not found on PATH. Install with: dotnet tool install -g Microsoft.DotNet.Tools.Dnx (requires .NET SDK 8.0+)"}\n'
    exit 1
fi
echo "dnx found at: $(command -v dnx)" >&2

# 2. Probe package resolution (lightweight — just check if dnx can locate the tool)
if dnx "$PACKAGE" --help --prerelease --source "$FEED" >/dev/null 2>&1; then
    printf '{"dnxFound":true,"packageResolvable":true,"error":null}\n'
    exit 0
else
    printf '{"dnxFound":true,"packageResolvable":false,"error":"dnx exited with non-zero. The MCP package may not be resolvable — check network access to %s"}\n' "$FEED"
    exit 1
fi
