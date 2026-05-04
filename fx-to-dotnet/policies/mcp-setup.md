# MCP Server Setup: Modernization

## Policy

The `fx-to-dotnet-assess` and `fx-to-dotnet-sdk-convert` commands require the `Microsoft.GitHubCopilot.Modernization.Mcp` MCP server. This server provides project analysis and SDK-style conversion tools. It is distributed as a NuGet tool package run via `dnx` — it is fetched at runtime, not bundled with the extensions. The `--prerelease` flag ensures the latest prerelease version is always used.

The MCP config file location and top-level schema key depend on which IDE the user is running. Auto-configuration is **always workspace-scoped** (per-repo); user-scoped paths are documented for reference but never written by this workflow.

## Host Matrix

| Host | Workspace config path | Top-level key | Detection signal (workspace-relative) |
|------|-----------------------|---------------|---------------------------------------|
| Visual Studio 2022 (17.14+) | `<solutionDir>/.mcp.json` | `mcpServers` | `.vs/` directory, or `*.suo` next to `.sln` |
| VS Code (1.102+) | `.vscode/mcp.json` | `servers` | `.vscode/` directory |
| Cursor | `.cursor/mcp.json` | `mcpServers` | `.cursor/` directory |
| Windsurf | `.windsurf/mcp.json` | `mcpServers` | `.windsurf/` or `.codeium/` directory |
| JetBrains / Junie | `.junie/mcp.json` | `mcpServers` | `.idea/` directory or `*.iml` files |
| Generic / Claude Code (fallback) | `.mcp.json` (workspace root) | `mcpServers` | none of the above |

> **Schema note:** VS Code uses the top-level key `servers`; every other host uses `mcpServers`. The inner server definition is identical across hosts.

## Canonical Server Entry — `mcpServers` variant (Visual Studio, Cursor, Windsurf, JetBrains, generic)

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

## Canonical Server Entry — `servers` variant (VS Code only)

```json
{
  "servers": {
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

## Host Detection

Apply these rules **in order**; the first match wins. Use `list_dir` (or equivalent) on the workspace root, or `read` to probe for files. Detection is filesystem-based; only fall through to `ask-questions` when two or more host signals are present at the same precedence tier.

1. **Visual Studio 2022** — workspace contains `.vs/` directory, or a `*.suo` file alongside the target `.sln`.
2. **VS Code** — workspace contains `.vscode/` directory.
3. **Cursor** — workspace contains `.cursor/` directory.
4. **Windsurf** — workspace contains `.windsurf/` or `.codeium/` directory.
5. **JetBrains / Junie** — workspace contains `.idea/` directory or any `*.iml` file.
6. **Generic fallback** — none of the above; use workspace-root `.mcp.json`.

If signals from steps 1–5 are simultaneously present (e.g., `.vs/` and `.vscode/` both exist because the user opens the same repo in multiple IDEs), use `ask-questions` to let the user pick the host. Visual Studio is intentionally checked **before** VS Code so that solutions opened primarily in VS aren't misrouted by an incidental `.vscode/` folder.

## Detection (server-entry check)

1. Determine the active host using **Host Detection** above. From the **Host Matrix**, derive `{configPath}` (relative to workspace root) and `{topKey}` (`servers` or `mcpServers`).
2. Use the `read` tool to read `{configPath}`.
3. If the read succeeds, check whether the JSON contains a `Microsoft.GitHubCopilot.Modernization.Mcp` key under `{topKey}`.
4. If the key exists, the server is configured — proceed with the command workflow.

## Remediation

If `{configPath}` does not exist or does not contain the required entry:

1. Use `ask-questions` to present the user with options:
   - **"Configure automatically"** — create or patch `{configPath}` with the required entry
   - **"I'll configure it manually"** — display the canonical snippet for `{topKey}` above and stop
2. If the user chooses automatic configuration:
   - Pick the snippet matching `{topKey}` (`servers` for VS Code, `mcpServers` otherwise).
   - If `{configPath}` does not exist, create it (and any parent directory such as `.vscode/`) with the full canonical content for `{topKey}` using the `edit` tool.
   - If `{configPath}` exists but lacks the `Microsoft.GitHubCopilot.Modernization.Mcp` entry, merge the server entry into the existing `{topKey}` object using the `edit` tool — preserve all other server entries.
3. After writing, instruct the user: **"Reload your IDE window (VS Code: `Ctrl+Shift+P` → `Developer: Reload Window`; otherwise restart the IDE) so the MCP server starts, then re-run this command."**
4. **Stop** — do not proceed to MCP tool calls until the server is available.

## Notes

- The `--yes` flag auto-accepts the .NET tool trust prompt.
- The `--prerelease` flag ensures `dnx` fetches the latest prerelease version without requiring a pinned version string.
- The `--source` flag ensures the package is fetched from NuGet.org even if local NuGet config overrides the default feed.
- VS Code uses the `servers` top-level key (not `mcpServers`); this is a divergence from the broader MCP ecosystem and is preserved by VS Code for backward compatibility.
- User-scoped MCP config paths exist for every host (e.g., `~/.cursor/mcp.json`, `%APPDATA%\Code\User\mcp.json`) but are intentionally **out of scope** for this workflow — auto-configuration always writes workspace-scoped files so the config travels with the repo.
- Most hosts discover their MCP config on IDE start; some (VS Code) support hot-reload via the reload-window command above.
