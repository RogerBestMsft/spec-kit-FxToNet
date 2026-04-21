# Plan: Pre-flight MCP Server Check in Consuming Commands

## TL;DR

Add a pre-flight check to the two spec-kit commands that depend on `Microsoft.GitHubCopilot.AppModernization.Mcp` (`assess` and `convert`). Before calling any MCP tools, each command checks the workspace `.mcp.json` for the AppModernization entry and offers to create/patch it if missing. The MCP configuration snippet lives in a shared policy doc in `fx-to-dotnet-policies` so both commands reference a single source of truth.

---

## Motivation

When a user installs the spec-kit extensions via `specify extension add`, the `extension.yml` files declare `Microsoft.GitHubCopilot.AppModernization.Mcp` as a `requires.tools` entry — Spec Kit warns if the tool is unavailable, but does not configure it. Users must manually create a `.mcp.json` in their workspace with the correct server entry. This is a common source of friction: the command fails at the first MCP tool call with no actionable guidance.

A pre-flight check detects the missing config at the earliest possible moment and offers to fix it automatically, before any MCP-dependent work begins.

---

## Design

### Shared Policy Document

A new policy doc (`mcp-setup.md`) in `fx-to-dotnet-policies` serves as the single source of truth for:

- The canonical `.mcp.json` snippet (server name, type, command, args with pinned version, tools)
- Detection logic (how to check if the entry is present)
- Remediation logic (create or merge)
- Post-remediation note (reload window for VS Code to start the server)

Both consuming commands reference this policy rather than duplicating the config inline. When the MCP server version is bumped, only `mcp-setup.md` needs updating.

### Pre-flight Behavior

Inserted as the first step in the Initialize workflow of each command:

1. Use the `read` tool to attempt to read `.mcp.json` from the workspace root
2. If the file does not exist, or exists but does not contain the `Microsoft.GitHubCopilot.AppModernization.Mcp` key under `mcpServers`:
   - Reference `fx-to-dotnet-policies/policies/mcp-setup.md` for the expected configuration
   - Use `ask-questions` to present the user with options:
     - **"Configure automatically"** — create or patch `.mcp.json` with the required entry
     - **"I'll configure it manually"** — display the required snippet and stop
   - If the user chooses automatic configuration, use `edit` to create or merge the entry into `.mcp.json`
   - Instruct the user to reload the VS Code window (or wait for auto-detection) so the MCP server starts, then retry the command
   - **Stop** — do not proceed to MCP tool calls until the server is available
3. If the entry is already present, proceed silently

### Why Not Other Approaches

| Alternative | Why not |
|---|---|
| Extend `extension.yml` schema with `provides.mcp_servers` | Requires a Spec Kit schema change and CLI implementation — out of scope |
| Dedicated `setup` command | Extra step the user must discover and remember to run |
| VS Code user-level `settings.json` config | Global scope — user may not want the server everywhere; version pinning becomes workspace-independent |

The pre-flight approach works today with no schema changes, triggers exactly when needed, and keeps the fix co-located with the failure.

---

## Steps

### Phase 1: Shared Policy Document

#### 1. Create `spec-kit/fx-to-dotnet-policies/policies/mcp-setup.md`

New policy doc containing:

```markdown
# MCP Server Setup: AppModernization

## Required Configuration

The `fx-to-dotnet-assess` and `fx-to-dotnet-sdk-convert` commands require the
`Microsoft.GitHubCopilot.AppModernization.Mcp` MCP server. This server provides
project analysis and SDK-style conversion tools.

## Canonical `.mcp.json` Entry

{the pinned .mcp.json snippet from the repo root}

## Detection

1. Read `.mcp.json` from the workspace root using the `read` tool
2. Parse the JSON and check for `mcpServers.Microsoft.GitHubCopilot.AppModernization.Mcp`
3. If the key exists, the server is configured — proceed

## Remediation

If the key is missing or the file does not exist:

1. Ask the user for confirmation before modifying workspace configuration
2. If `.mcp.json` does not exist, create it with the full canonical content
3. If `.mcp.json` exists but lacks the entry, merge the server entry into the
   existing `mcpServers` object (preserve other servers)
4. After writing, instruct the user to reload the VS Code window so the MCP
   server starts, then retry the command

## Notes

- The MCP server is a NuGet tool package run via `dnx` — it is fetched at
  runtime, not bundled with the extensions
- The `--yes` flag auto-accepts the .NET tool trust prompt
- Version is pinned; update this policy when bumping the server version
```

#### 2. Update `spec-kit/fx-to-dotnet-policies/commands/show.md`

Add `mcp-setup` to the list of displayable policies.

#### 3. Update `spec-kit/fx-to-dotnet-policies/README.md`

Add row to the policy reference table:

| Policy | File | Description |
|--------|------|-------------|
| `mcp-setup` | `policies/mcp-setup.md` | MCP server detection and auto-configuration for AppModernization tools |

### Phase 2: Pre-flight in `assess` Command

#### 4. Edit `spec-kit/fx-to-dotnet-assess/commands/assess.md`

Insert an `#### MCP Server Pre-flight` subsection inside `### 1. Initialize`, **before** the existing `#### Resume Check` block:

```markdown
#### MCP Server Pre-flight

Before any MCP tool calls, verify the workspace has the required MCP server configured:

1. Use the `read` tool to read `.mcp.json` from the workspace root (same directory as the solution file or its parent)
2. If the read fails (file does not exist) or the JSON does not contain a `Microsoft.GitHubCopilot.AppModernization.Mcp` key under `mcpServers`:
   - Reference `fx-to-dotnet-policies/policies/mcp-setup.md` for the canonical configuration
   - Ask the user:
     - **"Configure automatically"** — create or patch `.mcp.json`
     - **"I'll configure it manually"** — show the snippet and stop
   - If auto-configuring, use the `edit` tool to write the file
   - Tell the user to reload the VS Code window, then retry this command
   - **Stop** — do not proceed until the MCP server is available
3. If the entry is present, continue to Resume Check
```

### Phase 3: Pre-flight in `convert` Command

#### 5. Edit `spec-kit/fx-to-dotnet-sdk-convert/commands/convert.md`

Insert a `### 0. MCP Server Pre-flight` section **before** the existing `## 1. Initialize`, inside the `<workflow>` block. Same logic as step 4, referencing the same shared policy doc.

### Phase 4: Documentation Updates

#### 6. Update `spec-kit/fx-to-dotnet-assess/README.md`

Add a note under Prerequisites:

> The `assess` command automatically detects if the AppModernization MCP server is not configured and offers to set it up.

#### 7. Update `spec-kit/fx-to-dotnet-sdk-convert/README.md`

Same note:

> The `convert` command automatically detects if the AppModernization MCP server is not configured and offers to set it up.

---

## Relevant Files

| File | Change |
|---|---|
| `spec-kit/fx-to-dotnet-policies/policies/mcp-setup.md` | **New** — canonical MCP config + detection/remediation instructions |
| `spec-kit/fx-to-dotnet-policies/commands/show.md` | Add `mcp-setup` to policy list |
| `spec-kit/fx-to-dotnet-policies/README.md` | Add `mcp-setup` to reference table |
| `spec-kit/fx-to-dotnet-assess/commands/assess.md` | Insert `#### MCP Server Pre-flight` in `### 1. Initialize` |
| `spec-kit/fx-to-dotnet-sdk-convert/commands/convert.md` | Insert `### 0. MCP Server Pre-flight` before `## 1. Initialize` |
| `spec-kit/fx-to-dotnet-assess/README.md` | Documentation note |
| `spec-kit/fx-to-dotnet-sdk-convert/README.md` | Documentation note |

---

## Verification

1. Read `spec-kit/fx-to-dotnet-policies/policies/mcp-setup.md` and confirm the `.mcp.json` snippet matches the canonical config in the repo root `.mcp.json`
2. Read `assess.md` and verify the pre-flight appears before any `get_state()` or MCP tool calls
3. Read `convert.md` and verify the pre-flight appears before the `convert_project_to_sdk_style` call
4. Verify both commands reference `fx-to-dotnet-policies/policies/mcp-setup.md` (not inline duplicated snippets)
5. Run `python scripts/cross-reference-audit.py` to confirm no broken cross-extension references
6. Manual: install the extensions without `.mcp.json` in a test workspace, invoke `assess` or `convert`, and verify the pre-flight detects the missing config and offers to create it

---

## Decisions

| Decision | Rationale |
|---|---|
| **Shared policy doc, not duplicated inline** | Both commands reference `mcp-setup.md` — MCP version and config maintained in one place |
| **User confirmation required** | `ask-questions` before writing `.mcp.json` — it's a workspace config file the user should be aware of |
| **Pre-flight placement** | In `assess`: inside Initialize, before Resume Check. In `convert`: new step 0 before Initialize |
| **Scope: only `assess` and `convert`** | These are the only commands declaring AppModernization MCP tools; other commands don't call MCP tools directly |
| **No `extension.yml` schema change** | `requires.tools` stays as-is for Spec Kit's built-in warning; pre-flight is additive |
| **Stop after config, don't auto-retry** | The MCP server needs VS Code to detect the new `.mcp.json` and start the process — retrying immediately would fail |
