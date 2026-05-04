---
description: "Generate tasks.md from plan.md (preset override for fx-to-dotnet integration)."
---
# Tasks Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.tasks` body to coordinate with the `fx-to-dotnet` extension (v0.4.0+).

> **Extension-coordination directive** — If `.specify/extensions.yml` enables `fx-to-dotnet`, you MUST NOT generate migration-themed tasks. The `after_tasks` hook (`speckit.fx-to-dotnet.tasks-hook`) owns migration task emission and will populate the migration phase block. Emitting your own migration tasks here causes the hook to dedupe them, producing wasted work and confusing diffs.

<workflow>

## 1. Detect extension presence

Inspect `.specify/extensions.yml`. If `fx-to-dotnet` is listed and enabled, set `EXTENSION_ACTIVE = true`. Otherwise behave as core.

## 2. Generate user-story tasks

Generate `[US*]` user-story tasks from `plan.md` exactly as core does, EXCLUDING any task that:

- Mentions SDK conversion, SDK-style projects, multitarget, target framework upgrades, NuGet/package updates, framework migration, or "migrate to .NET"
- References any `## .NET Migration Plan` or `## Migration Assessment Summary` section in `plan.md` (these are extension-managed; never source tasks from them)

## 3. Migration phase placeholder

If `EXTENSION_ACTIVE` is true, emit ONLY a placeholder migration phase heading at the position where the migration phase will appear (immediately before the first user-story phase):

```
## Phase N: .NET Framework Migration (extension-managed)

> **Extension-managed placeholder** — the `fx-to-dotnet` extension's `after_tasks` hook will replace this heading with a populated `## Phase N: .NET Framework Migration` block containing `[MIG-*]` tasks. Do not edit by hand.
```

Do NOT emit any `[MIG-*]` tasks. Do NOT emit any task that the migration hook would dedupe.

If `EXTENSION_ACTIVE` is false, omit the placeholder entirely and behave as core.

## 4. User-story phases follow

After the placeholder (or directly, if no extension), continue with the standard user-story phases.

</workflow>

<contracts>
- The `after_tasks` hook is the single source of truth for migration tasks.
- Core never dispatches `[MIG-*]` tasks during `/speckit.implement`; the `before_implement` hook does.
- This override is purely additive in behavior — it removes migration content and adds a placeholder; it does not change user-story task generation.
</contracts>
