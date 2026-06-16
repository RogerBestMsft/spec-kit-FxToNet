---
description: "Generate plan.md from spec.md (preset override for fx-to-dotnet integration). Defers migration analysis and plan ownership to the extension after_plan hook."
---
# Plan Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.plan` body to coordinate with the `fx-to-dotnet` extension. It does not generate migration analysis content in `plan.md`; the `after_plan` hook owns migration assessment and extension-managed plan sections.

> **Extension-coordination directive** — If `.specify/extensions.yml` enables `fx-to-dotnet`, you MUST NOT generate migration-themed technical analysis in `plan.md` (for example dependency layers, upgrade strategies, policy signal tables, or migration phase breakdowns). The mandatory `after_plan` hook (`speckit.fx-to-dotnet.plan-hook`) is the single source of truth for migration analysis artifacts and plan annotations.

<workflow>

## 1. Detect extension presence

Inspect `.specify/extensions.yml`. If `fx-to-dotnet` is listed and enabled, set `EXTENSION_ACTIVE = true`. Otherwise behave as core.

## 2. Run core plan workflow

Execute the standard `speckit.plan` workflow in full — load the spec, produce `plan.md` with Technical Context, Constitution Check, research.md, data-model.md, contracts/, and quickstart.md. Do not alter the core behavior.

## 3. Migration section handling

If `EXTENSION_ACTIVE` is true:

- Do NOT add `## Migration Technical Analysis` or any other migration-owned section to `plan.md`.
- Do NOT synthesize migration dependency layers, upgrade strategy classifications, policy application tables, or migration phase breakdowns in this command.
- Reserve migration plan ownership for the extension-managed `## .NET Migration Plan` section written by `speckit.fx-to-dotnet.plan-hook` after this command completes.

If `EXTENSION_ACTIVE` is false, behave as core.

## 4. Continue

The plan workflow is complete. When `EXTENSION_ACTIVE` is true, migration analysis and extension-managed plan annotations are produced by the mandatory `after_plan` hook.

</workflow>

<contracts>
- The `after_plan` hook is the single source of truth for migration analysis and plan annotations.
- This override prevents competing migration content in `plan.md`; it does not alter core plan generation for non-migration content.
</contracts>
