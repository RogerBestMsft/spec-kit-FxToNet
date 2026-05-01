---
name: ef6-migration-policy
description: "EF6 to EF Core migration policy for .NET Framework to modern .NET upgrades. Use when: assessing EF6 usage, planning package compatibility, multitargeting projects with Entity Framework 6. EF Core is NOT supported on .NET Framework — EF6 packages must be retained during framework-to-modern-dotnet migration and only migrated to EF Core as a separate post-migration effort."
---

# EF6 Migration Policy

## Policy

Entity Framework 6 (EF6) must NOT be migrated to Entity Framework Core (EF Core) during a .NET Framework to modern .NET migration. EF Core does not support .NET Framework, and replacing EF6 with EF Core during the framework migration introduces unnecessary risk and scope.

## Rules

1. **Retain EF6 during migration** — Keep `EntityFramework` / `EntityFramework.SqlServer` packages throughout SDK conversion, package compatibility, and multitargeting phases
2. **Do not replace EF6 with EF Core** — Never swap `EntityFramework` for `Microsoft.EntityFrameworkCore.*` as part of the framework migration
3. **EF6 is compatible with modern .NET** — The `EntityFramework` 6.5+ package supports `net8.0`+ via `netstandard2.1`. Upgrade to the minimum EF6 version that supports the target framework
4. **EF Core migration is a separate effort** — Migrating from EF6 to EF Core is a post-migration activity, performed only after the project fully runs on modern .NET
5. **Assessment should flag, not act** — When EF6 usage is detected during assessment, note it as a future post-migration task, not a migration blocker or in-scope work item

## When This Applies

- **Package compatibility analysis**: Do not flag EF6 as incompatible. Find the minimum EF6 version supporting the target framework.
- **Multitarget migration**: EF6 APIs are available on modern .NET via EF6 6.5+. Do not introduce `#if` guards to swap EF6 for EF Core.
- **Assessment reports**: List EF6 usage as a post-migration consideration, not as a migration action item.
- **SDK-style conversion**: `EntityFramework` PackageReference should be preserved as-is.

## What NOT to Do

- Do not add `Microsoft.EntityFrameworkCore` packages during any migration phase
- Do not remove or replace `EntityFramework` references
- Do not treat EF6 DbContext/model classes as migration blockers
- Do not create EF Core DbContext alternatives during framework migration
