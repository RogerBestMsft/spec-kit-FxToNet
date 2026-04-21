# fx-to-dotnet-plan — Migration Planner

Synthesize assessment findings into an actionable, layered migration plan with chunked package updates.

## Command

`speckit.fx-to-dotnet-plan.plan` — Accepts assessment content, topological projects, dependency layers, solution path, and target framework.

## Prerequisites

- `fx-to-dotnet-policies` — for migration policy references

## State Files

- Reads: `.fx-to-dotnet/analysis.md`, `.fx-to-dotnet/package-updates.md`
- Output: structured migration plan returned to caller (appended to `.fx-to-dotnet/plan.md` by orchestrator)
