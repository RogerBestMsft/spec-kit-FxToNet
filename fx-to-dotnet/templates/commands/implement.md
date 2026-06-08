---
description: "Execute tasks.md (preset override for fx-to-dotnet integration). Runs Setup tasks first, then hands off to the before_implement hook for [MIG-*] migration tasks, then continues with remaining user-story phases."
---
# Implement Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.implement` body to coordinate with the `fx-to-dotnet` extension (v0.4.0+).

> **Extension-coordination directive** — If `.specify/extensions.yml` enables `fx-to-dotnet`, this template enforces a **two-invocation model**: the first `/speckit.implement` runs Phase 1 Setup `[US*]` tasks, then stops at the Migration phase boundary. The second `/speckit.implement` triggers the `before_implement` hook, which processes all `[MIG-*]` tasks via its dispatch loop, then core resumes for the remaining user-story phases. You MUST NOT interpret or dispatch any `[MIG-*]` task yourself — the hook owns the entire migration execution loop.

<workflow>

## 1. Detect extension presence

Inspect `.specify/extensions.yml`. If `fx-to-dotnet` is enabled, set `EXTENSION_ACTIVE = true`.

## 2. Handle [MIG-*] tasks with phase awareness

Iterate through `tasks.md` in document order. For every task whose ID matches `^MIG-\d{3}$`:

- Do NOT execute it
- Do NOT parse its `dispatch:` trailer
- Do NOT invoke any command from a non-`speckit.fx-to-dotnet.*` namespace on its behalf
- If already marked `[X]` or `[~]`: treat as completed, skip
- If any `[MIG-*]` task is still `[ ]` (unchecked):
  - Determine whether all Setup phase `[US*]` tasks are complete by scanning `tasks.md` for the Setup phase heading (a `## Phase N:` heading whose title matches `/setup/i`) and checking that every `[US*]` task under it is `[X]`.
  - **If Setup is NOT complete**: this should not occur (the `before_implement` hook only passes through when Setup is incomplete, and Setup tasks precede Migration in document order). ABORT with:

    ```
    ERROR: Setup tasks incomplete but [MIG-*] tasks encountered. This is unexpected.
    Ensure Phase 1 Setup tasks are completed before migration tasks.
    Re-run `/speckit.implement`.
    ```

  - **If Setup IS complete**: the `before_implement` hook deferred because it was the first invocation after Setup finished. **Stop gracefully** and ask:

    ```
    Setup phase complete. Migration tasks are ready for execution.
      continue           — run `/speckit.implement` again to review each migration task individually
      autoApprove-rest   — run `/speckit.implement` again and auto-approve all migration tasks
                           (build failures still pause for review)
    ```

    - If `autoApprove-rest` selected: write or update `{featureDir}/migration/implement-state.md` to set `Outer gate mode: autoApprove-rest`. The `before_implement` hook will read this on the next invocation and skip outer review prompts for all `[MIG-*]` tasks.
    - If `continue` selected: ensure `implement-state.md` has `Outer gate mode: prompt` (or leave it absent — the hook defaults to `prompt`).
    - Exit gracefully after writing the preference. This is NOT an error.

## 3. Execute user-story tasks

Process `[US*]` tasks exactly as core does. The `> ✓ Migration Complete` checkpoint inserted by the `before_implement` hook serves as the boundary marker; you may treat it as informational.

On the first invocation (Setup not yet complete), this step processes Phase 1 Setup tasks and then reaches the `[MIG-*]` boundary handled by step 2. On subsequent invocations (after the hook has resolved all `[MIG-*]` tasks), this step skips Setup `[X]` and Migration `[X]`/`[~]` and continues with Phase 3 Foundational and later user-story phases.

## 4. Dispatch namespace restriction

When `EXTENSION_ACTIVE` is true, you MUST NOT dispatch any `speckit.fx-to-dotnet.*` command on behalf of a `[MIG-*]` task. The hook is the sole authorized invoker of those commands for migration items. (User-story `[US*]` tasks may legitimately call non-migration commands as usual.)

</workflow>

<contracts>
- Goal 5 of the tight integration plan: only `speckit.fx-to-dotnet.*` commands run for migration items, and only via the hook. This override is the deterministic enforcement at the core-command layer.
- Hook-managed: precondition gate, dispatch validation, per-task review, build-failure pause, audit log.
- The two-invocation model ensures Phase 1 Setup (shared infrastructure) completes before any migration work begins, so that migration commands operate on projects that already have logging, DI, and config patterns in place.
- `autoApprove-rest` is persisted to `implement-state.md` only when the user explicitly opts in at the Setup-complete prompt. The `before_implement` hook consumes and resets it after the `[MIG-*]` loop completes.
</contracts>
