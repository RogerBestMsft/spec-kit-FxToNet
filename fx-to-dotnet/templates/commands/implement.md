---
description: "Execute tasks.md (preset override for fx-to-dotnet integration)."
---
# Implement Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.implement` body to coordinate with the `fx-to-dotnet` extension (v0.4.0+).

> **Extension-coordination directive** — If `.specify/extensions.yml` enables `fx-to-dotnet`, you MUST NOT interpret or dispatch any `[MIG-*]` task. The `before_implement` hook (`speckit.fx-to-dotnet.implement-hook`) owns the migration execution loop, including prerequisite gating, per-task user review, and dispatch validation. Core may execute ordinary prerequisite tasks that appear before the first unresolved `[MIG-*]` row, but it must stop at the unresolved migration boundary and let the hook own everything from there.

<workflow>

## 1. Detect extension presence

Inspect `.specify/extensions.yml`. If `fx-to-dotnet` is enabled, set `EXTENSION_ACTIVE = true`.

## 2. Execute prerequisite tasks ahead of migration

Iterate through `tasks.md` in document order.

If extension-managed migration content exists and there are unchecked non-`[MIG-*]` tasks before the first unresolved `[MIG-*]` row, execute only those prerequisite tasks on this pass using the normal core behavior for ordinary tasks.

These prerequisite tasks are the only non-hook work allowed before migration dispatch begins.

## 3. Stop at unresolved migration boundary

For every task whose ID matches `^MIG-\d{3}$`:

- Do NOT execute it
- Do NOT parse its `dispatch:` trailer
- Do NOT invoke any command from a non-`speckit.fx-to-dotnet.*` namespace on its behalf
- Treat already-marked `[X]` and `[~]` rows as completed.
- If an unresolved `[ ]` row is encountered and there were prerequisite tasks earlier in the file on this pass, STOP after the prerequisite segment and tell the user to re-run `/speckit.implement` so the hook can process migration now that prerequisites are complete.
- If an unresolved `[ ]` row is encountered and there were no prerequisite tasks earlier in the file, treat it as a hook failure and ABORT with a remediation message:

  ```
  ERROR: Unresolved [MIG-*] tasks detected. The `before_implement` hook should have processed these.
  Re-run `/speckit.implement` to invoke the hook, or `speckit.fx-to-dotnet.implement-hook` directly.
  ```

## 4. Execute user-story tasks

Process `[US*]` tasks exactly as core does, but only after the migration boundary has been cleared. The `> ✓ Migration Complete` checkpoint inserted by the `before_implement` hook serves as the boundary marker; you may treat it as informational.

## 5. Dispatch namespace restriction

When `EXTENSION_ACTIVE` is true, you MUST NOT dispatch any `speckit.fx-to-dotnet.*` command on behalf of a `[MIG-*]` task. The hook is the sole authorized invoker of those commands for migration items. (User-story `[US*]` tasks may legitimately call non-migration commands as usual.)

</workflow>

<contracts>
- Goal 5 of the tight integration plan: only `speckit.fx-to-dotnet.*` commands run for migration items, and only via the hook. This override is the deterministic enforcement at the core-command layer.
- Hook-managed: precondition gate, prerequisite deferral, dispatch validation, per-task review, build-failure pause, audit log.
</contracts>
