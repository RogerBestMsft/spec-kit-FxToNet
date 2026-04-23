# MCP Server Setup: Modernization

## Policy

The `fx-to-dotnet-assess` and `fx-to-dotnet-sdk-convert` commands require the `Microsoft.GitHubCopilot.Modernization.Mcp` MCP server. This server provides project analysis and SDK-style conversion tools. It is distributed as a NuGet tool package run via `dnx` — it is fetched at runtime, not bundled with the extensions. The `--prerelease` flag ensures the latest prerelease version is always used.

## Canonical `.mcp.json` Entry

```json
{
  "mcpServers": {
    "Microsoft.GitHubCopilot.Modernization.Mcp": {
      "type": "stdio",
      "command": "dnx",
      "args": [
        "Microsoft.GitHubCopilot.Modernization.Mcp",
        "--yes",
        "--prerelease",
        "--source",
        "https://api.nuget.org/v3/index.json"
      ],
      "tools": [
        "*"
      ]
    }
  }
}
```

**Version**: Latest prerelease — `dnx` resolves the newest prerelease version automatically via the `--prerelease` flag. No pinned version to maintain.

## Detection

1. Use the `read` tool to read `.mcp.json` from the workspace root (the directory containing the solution file, or its parent)
2. If the read succeeds, check whether the JSON contains a `Microsoft.GitHubCopilot.Modernization.Mcp` key under `mcpServers`
3. If the key exists, the server is configured — proceed with the command workflow

## Remediation

If `.mcp.json` does not exist or does not contain the required entry:

1. Use `ask-questions` to present the user with options:
   - **"Configure automatically"** — create or patch `.mcp.json` with the required entry
   - **"I'll configure it manually"** — display the canonical snippet above and stop
2. If the user chooses automatic configuration:
   - If `.mcp.json` does not exist, create it with the full canonical content above using the `edit` tool
   - If `.mcp.json` exists but lacks the `Microsoft.GitHubCopilot.Modernization.Mcp` entry, merge the server entry into the existing `mcpServers` object using the `edit` tool — preserve all other server entries
3. After writing, instruct the user: **"Reload the VS Code window (`Ctrl+Shift+P` → `Developer: Reload Window`) so the MCP server starts, then re-run this command."**
4. **Stop** — do not proceed to MCP tool calls until the server is available

## Notes

- The `--yes` flag auto-accepts the .NET tool trust prompt
- The `--prerelease` flag ensures `dnx` fetches the latest prerelease version without requiring a pinned version string
- The `--source` flag ensures the package is fetched from NuGet.org even if local NuGet config overrides the default feed
- VS Code discovers `.mcp.json` files at workspace root and starts MCP servers on demand
