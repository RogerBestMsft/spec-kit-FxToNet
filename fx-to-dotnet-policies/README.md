# fx-to-dotnet-policies — Shared Migration Policies

Shared migration policy documents for .NET Framework to modern .NET migration.

## Command

`speckit.fx-to-dotnet-policies.show` — Display a named migration policy document.

## Available Policies

| Policy | File | Description |
|--------|------|-------------|
| `ef6-retention` | `policies/ef6-retention.md` | EF6 must NOT be migrated to EF Core during framework migration |
| `mcp-setup` | `policies/mcp-setup.md` | MCP server detection and auto-configuration for AppModernization tools |
| `owin-identity` | `policies/owin-identity.md` | Use OWIN compatibility shims for ASP.NET Identity |
| `systemweb-adapters` | `policies/systemweb-adapters.md` | System.Web adapters as default migration approach |
| `windows-service` | `policies/windows-service.md` | ServiceBase → BackgroundService migration |

## Prerequisites

None — this extension is self-contained.

## State Files

None — policy documents are read-only references.
