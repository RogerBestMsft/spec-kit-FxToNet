---
description: "Execute tasks.md (preset override for fx-to-dotnet integration)."
---
# Implement Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.implement` body to coordinate with the `fx-to-dotnet` extension (v0.4.0+).

> **Extension-coordination directive** — If `.specify/extensions.yml` enables `fx-to-dotnet`, you MUST NOT interpret or dispatch any `[MIG-*]` task. The `before_implement` hook (`speckit.fx-to-dotnet.implement-hook`) owns the entire migration execution loop, including per-task user review and dispatch validation. By the time core resumes here, all `[MIG-*]` tasks will be marked `[X]` (approved), `[~]` (skipped), or the hook will have aborted the run.

<workflow>

## 1. Detect extension presence

Inspect `.specify/extensions.yml`. If `fx-to-dotnet` is enabled, set `EXTENSION_ACTIVE = true`.

## 2. Skip [MIG-*] tasks unconditionally

Iterate through `tasks.md` in document order. For every task whose ID matches `^MIG-\d{3}$`:

- Do NOT execute it
- Do NOT parse its `dispatch:` trailer
- Do NOT invoke any command from a non-`speckit.fx-to-dotnet.*` namespace on its behalf
- Treat already-marked `[X]` and `[~]` rows as completed; treat any remaining `[ ]` as a hook failure (the `before_implement` gate should have resolved them all) and ABORT with a remediation message:

  ```
  ERROR: Unresolved [MIG-*] tasks detected. The `before_implement` hook should have processed these.
  Re-run `/speckit.implement` to invoke the hook, or `speckit.fx-to-dotnet.implement-hook` directly.
  ```

## 3. Execute user-story tasks

Process `[US*]` tasks exactly as core does. The `> ✓ Migration Complete` checkpoint inserted by the `before_implement` hook serves as the boundary marker; you may treat it as informational.

## 4. Dispatch namespace restriction

When `EXTENSION_ACTIVE` is true, you MUST NOT dispatch any `speckit.fx-to-dotnet.*` command on behalf of a `[MIG-*]` task. The hook is the sole authorized invoker of those commands for migration items. (User-story `[US*]` tasks may legitimately call non-migration commands as usual.)

</workflow>

<contracts>
- Goal 5 of the tight integration plan: only `speckit.fx-to-dotnet.*` commands run for migration items, and only via the hook. This override is the deterministic enforcement at the core-command layer.
- Hook-managed: precondition gate, dispatch validation, per-task review, build-failure pause, audit log.
</contracts>
