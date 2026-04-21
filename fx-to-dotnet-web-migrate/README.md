# fx-to-dotnet-web-migrate — ASP.NET Web Migration

Plan and execute ASP.NET Framework to ASP.NET Core migration; create side-by-side host; port artifacts in slices.

## Command

`speckit.fx-to-dotnet-web-migrate.migrate` — Required: legacy web project path. Optional: solution path and target framework.

## Prerequisites

- `fx-to-dotnet-route-inventory` — for endpoint and route discovery
- `fx-to-dotnet-build-fix` — for build validation after each slice
- `fx-to-dotnet-policies` — for System.Web adapters and OWIN identity policies

## State Files

- Reads/writes: `.fx-to-dotnet/{ProjectName}.md` (`## Web Migration` section)
