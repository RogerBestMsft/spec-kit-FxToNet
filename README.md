# fx-to-dotnet Extension Family

A family of **11 standalone Spec Kit extensions** that together orchestrate migrating .NET Framework applications to modern .NET (e.g. .NET 10) through a 7-phase workflow.

## Phase Diagram

```mermaid
graph TD
    A[speckit.fx-to-dotnet.orchestrate] --> B[Phase 1: Assessment]
    B --> C[Phase 2: Planning]
    C --> D[Phase 3: SDK Conversion]
    D --> E[Phase 4: Package Compatibility]
    E --> F[Phase 5: Multitarget Migration]
    F --> G[Phase 6: Web Migration]
    G --> H[Phase 7: Completion]

    B -.-> B1[fx-to-dotnet-assess]
    B1 -.-> B2[fx-to-dotnet-detect-project]
    C -.-> C1[fx-to-dotnet-plan]
    D -.-> D1[fx-to-dotnet-sdk-convert]
    D1 -.-> D2[fx-to-dotnet-build-fix]
    E -.-> E1[fx-to-dotnet-package-compat]
    E1 -.-> D2
    F -.-> F1[fx-to-dotnet-multitarget]
    F1 -.-> D2
    G -.-> G1[fx-to-dotnet-web-migrate]
    G1 -.-> G2[fx-to-dotnet-route-inventory]
    G1 -.-> D2

    style A fill:#4a9eff
    style B1 fill:#6cc644
    style C1 fill:#6cc644
    style D1 fill:#6cc644
    style D2 fill:#f9a825
    style E1 fill:#6cc644
    style F1 fill:#6cc644
    style G1 fill:#6cc644
    style B2 fill:#9c27b0
    style G2 fill:#9c27b0
```

## Extensions

| Extension | Command | Description |
|-----------|---------|-------------|
| `fx-to-dotnet` | `speckit.fx-to-dotnet.orchestrate` | Orchestrator — drives 7-phase flow |
| `fx-to-dotnet-assess` | `speckit.fx-to-dotnet-assess.assess` | Phase 1: Assessment |
| `fx-to-dotnet-plan` | `speckit.fx-to-dotnet-plan.plan` | Phase 2: Migration planning |
| `fx-to-dotnet-sdk-convert` | `speckit.fx-to-dotnet-sdk-convert.convert` | Phase 3: SDK-style conversion |
| `fx-to-dotnet-build-fix` | `speckit.fx-to-dotnet-build-fix.fix` | Cross-cutting: build/fix loop |
| `fx-to-dotnet-package-compat` | `speckit.fx-to-dotnet-package-compat.update` | Phase 4: Package compatibility |
| `fx-to-dotnet-multitarget` | `speckit.fx-to-dotnet-multitarget.migrate` | Phase 5: Multitarget migration |
| `fx-to-dotnet-web-migrate` | `speckit.fx-to-dotnet-web-migrate.migrate` | Phase 6: ASP.NET web migration |
| `fx-to-dotnet-detect-project` | `speckit.fx-to-dotnet-detect-project.detect` | Utility: project type detection |
| `fx-to-dotnet-route-inventory` | `speckit.fx-to-dotnet-route-inventory.inventory` | Utility: legacy route extraction |
| `fx-to-dotnet-policies` | `speckit.fx-to-dotnet-policies.show` | Shared policies + reference docs |

## Install All Extensions

```bash
for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan fx-to-dotnet-sdk-convert \
           fx-to-dotnet-build-fix fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
           fx-to-dotnet-web-migrate fx-to-dotnet-detect-project fx-to-dotnet-route-inventory \
           fx-to-dotnet-policies; do
  specify extension add $ext
done
```

### Dev Install (from local checkout)

```bash
for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan fx-to-dotnet-sdk-convert \
           fx-to-dotnet-build-fix fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
           fx-to-dotnet-web-migrate fx-to-dotnet-detect-project fx-to-dotnet-route-inventory \
           fx-to-dotnet-policies; do
  specify extension add --dev /path/to/$ext
done
```

## Prerequisites

- **Spec Kit** >= 0.5.0
- **.NET SDK** (for `dotnet build` via the build-fix extension)
- **MCP Servers** (required by assessment and SDK conversion extensions):
  - `Microsoft.GitHubCopilot.AppModernization.Mcp` — project analysis and SDK conversion
- **Skills** (bundled in the repo, used by assessment and SDK conversion):
  - `dependency-layers` — dependency layer computation algorithm
  - `nuget-package-compat` — NuGet package compatibility analysis scripts

### Sample MCP Configuration (`.mcp.json`)

```json
{
  "servers": {
    "Microsoft.GitHubCopilot.AppModernization.Mcp": {
      "type": "stdio",
      "command": "dotnet",
      "args": ["run", "--project", "<path-to-appmod-mcp-server>"]
    }
  }
}
```

## Dependency Graph

```
fx-to-dotnet (orchestrator)
├── fx-to-dotnet-assess
│   ├── fx-to-dotnet-detect-project
│   └── fx-to-dotnet-policies
├── fx-to-dotnet-plan
│   └── fx-to-dotnet-policies
├── fx-to-dotnet-sdk-convert
│   └── fx-to-dotnet-build-fix
│       └── fx-to-dotnet-policies
├── fx-to-dotnet-package-compat
│   └── fx-to-dotnet-build-fix
├── fx-to-dotnet-multitarget
│   ├── fx-to-dotnet-build-fix
│   └── fx-to-dotnet-policies
└── fx-to-dotnet-web-migrate
    ├── fx-to-dotnet-route-inventory
    ├── fx-to-dotnet-build-fix
    └── fx-to-dotnet-policies
```

## Standalone Usage

Some extensions can be used independently outside the full migration suite:

- **`fx-to-dotnet-build-fix`** — Useful for any .NET project; iteratively builds and fixes compilation errors
- **`fx-to-dotnet-detect-project`** — Classifies any .NET project (SDK-style, web host, service, library, etc.)
- **`fx-to-dotnet-route-inventory`** — Extracts endpoint inventory from any legacy ASP.NET web project

## License

MIT
