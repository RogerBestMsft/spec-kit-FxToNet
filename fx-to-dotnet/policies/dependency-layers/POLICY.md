---
name: dependency-layers
description: "Compute dependency layers from a project dependency graph using iterative graph reduction. Use when: ordering projects for migration, computing build layers, determining parallel migration batches, or topological layer grouping of solution projects."
---

# Dependency Layer Computation

Compute dependency layers for a set of projects by iterative graph reduction. Layer 1 contains projects with no in-scope dependencies; each subsequent layer depends only on earlier layers. Projects within the same layer are independent and can be processed in parallel.

## When to Use

- Computing migration order from a project dependency graph
- Determining which projects can be migrated in parallel
- Producing a layered build/migration plan for a solution

## Algorithm

Given a list of projects, each with a path and a list of dependency paths, compute layers as follows:

### Step 1 — Normalize Paths

For every project path and dependency path in the input:
- Replace all backslashes (`\`) with forward slashes (`/`)
- Convert to lowercase

This ensures case-insensitive, slash-insensitive matching. Preserve the **original** (un-normalized) path from the first occurrence of each project for display in output.

### Step 2 — Build Adjacency Map

For each project entry:
1. Compute its normalized key
2. Create a set of normalized dependency keys, including only dependencies that:
   - Exist in the input set (ignore external dependencies)
   - Are not the project itself (ignore self-dependencies)
3. If a project appears multiple times in the input, **merge** its dependency sets (union)

### Step 3 — Iterative Reduction

Set `layerNumber = 0`. While projects remain in the graph:

1. Find all projects whose dependency set is **empty** (zero remaining in-scope dependencies)
2. If none found → **break** (remaining projects form cycles)
3. Increment `layerNumber`
4. Record these projects as the current layer, sorted **alphabetically by original path** (case-insensitive)
5. Remove these projects from the graph
6. Remove these projects from all remaining dependency sets

### Step 4 — Cycle Detection

If any projects remain after the loop, they form unresolved cycles. Collect their original paths, sorted alphabetically (case-insensitive).

### Step 5 — Output

Return the result as JSON:

```json
{
  "layers": [
    { "layer": 1, "projects": ["path/to/A.csproj", "path/to/B.csproj"] },
    { "layer": 2, "projects": ["path/to/C.csproj"] }
  ],
  "unresolvedCycles": null,
  "error": null
}
```

- `layers` — array of `{ layer: number, projects: string[] }`, sorted by layer number
- `unresolvedCycles` — `null` if no cycles; otherwise an array of project paths involved in cycles
- `error` — `null` on success; a string message if the input is invalid

## Input Schema

```json
{
  "projects": [
    {
      "projectPath": "src/MyApp/MyApp.csproj",
      "dependencies": ["src/Common/Common.csproj", "src/Data/Data.csproj"]
    },
    {
      "projectPath": "src/Common/Common.csproj",
      "dependencies": []
    },
    {
      "projectPath": "src/Data/Data.csproj",
      "dependencies": ["src/Common/Common.csproj"]
    }
  ]
}
```

## Worked Example

**Input:**
```json
{
  "projects": [
    { "projectPath": "src/Web/Web.csproj", "dependencies": ["src/Services/Services.csproj", "src/Models/Models.csproj"] },
    { "projectPath": "src/Services/Services.csproj", "dependencies": ["src/Data/Data.csproj", "src/Models/Models.csproj"] },
    { "projectPath": "src/Data/Data.csproj", "dependencies": ["src/Models/Models.csproj"] },
    { "projectPath": "src/Models/Models.csproj", "dependencies": [] },
    { "projectPath": "src/CycleA/CycleA.csproj", "dependencies": ["src/CycleB/CycleB.csproj"] },
    { "projectPath": "src/CycleB/CycleB.csproj", "dependencies": ["src/CycleA/CycleA.csproj"] }
  ]
}
```

**Execution trace:**

| Iteration | Zero-dependency projects | Layer |
|-----------|--------------------------|-------|
| 1 | `src/Models/Models.csproj` | 1 |
| 2 | `src/Data/Data.csproj` | 2 |
| 3 | `src/Services/Services.csproj` | 3 |
| 4 | `src/Web/Web.csproj` | 4 |
| 5 | None found → break | — |

Remaining: `src/CycleA/CycleA.csproj`, `src/CycleB/CycleB.csproj`

**Output:**
```json
{
  "layers": [
    { "layer": 1, "projects": ["src/Models/Models.csproj"] },
    { "layer": 2, "projects": ["src/Data/Data.csproj"] },
    { "layer": 3, "projects": ["src/Services/Services.csproj"] },
    { "layer": 4, "projects": ["src/Web/Web.csproj"] }
  ],
  "unresolvedCycles": ["src/CycleA/CycleA.csproj", "src/CycleB/CycleB.csproj"],
  "error": null
}
```

## Validation Rules

- `projects` must be non-empty
- Each entry must have a non-empty `projectPath`
- If validation fails, return `{ "layers": [], "unresolvedCycles": null, "error": "<message>" }`
