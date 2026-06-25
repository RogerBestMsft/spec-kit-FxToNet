---
description: "Execute tasks.md (preset override for fx-to-dotnet integration)."
---
# Implement Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.implement` body to coordinate with the `fx-to-dotnet` extension (v0.4.0+).

> **Extension-coordination directive** — If `.specify/extensions.yml` enables `fx-to-dotnet`, you MUST NOT interpret or dispatch any `[MIG-*]` task. The `before_implement` hook (`speckit.fx-to-dotnet.implement-hook`) owns the migration execution loop, including prerequisite gating, per-task user review, and dispatch validation. Core may execute ordinary prerequisite tasks that appear before the first unresolved `[MIG-*]` row, but it must stop at the unresolved migration boundary and let the hook own everything from there.

<workflow>

## 1. Detect extension presence

Inspect `.specify/extensions.yml`. If `fx-to-dotnet` is enabled, set `EXTENSION_ACTIVE = true`.

## 2. Determine migration state and branch

Read `tasks.md` and classify the current state into exactly ONE of these three branches. Execute ONLY the matching branch — do NOT fall through to another branch.

### Branch A — Unresolved migration tasks exist

**Condition**: `tasks.md` contains at least one line matching `^- \[ \] \[MIG-\d{3}\]` (an unchecked `[MIG-*]` row).

**Action**: Execute ONLY non-`[MIG-*]` prerequisite tasks that appear before the first unresolved `[MIG-*]` row, using normal core behavior for ordinary tasks.

**Hard stop**: After executing prerequisites (or if none exist), you MUST EXIT immediately. Do NOT continue to any subsequent step. Do NOT process any `[US*]` task. Do NOT read or act on any task after the first unresolved `[MIG-*]` row. Tell the user:

```
Prerequisites complete. Re-run `/speckit.implement` so the `before_implement` hook can process migration tasks.
```

If no prerequisite tasks were executed on this pass either, ABORT with:

```
ERROR: Unresolved [MIG-*] tasks detected. The `before_implement` hook should have processed these.
Re-run `/speckit.implement` to invoke the hook, or `speckit.fx-to-dotnet.implement-hook` directly.
```

**You MUST NOT process any `[US*]` task on ANY pass where unresolved `[MIG-*]` tasks exist.** This is the critical ordering guarantee — migration (Phase 1) must complete before user-story phases can begin.

### Branch B — Migration complete

**Condition**: `tasks.md` contains the checkpoint line `> ✓ Migration Complete` (inserted by the `before_implement` hook after all `[MIG-*]` tasks are resolved).

**Action**: Process `[US*]` tasks exactly as core does. All `[MIG-*]` rows are already `[X]` or `[~]` — skip them.

### Branch C — No migration content

**Condition**: `tasks.md` contains no `[MIG-*]` rows and no `## Phase 1: .NET Framework Migration` heading (non-Framework workspace, or extension not active).

**Action**: Process all tasks using normal core behavior.

## 3. Dispatch namespace restriction

When `EXTENSION_ACTIVE` is true, you MUST NOT dispatch any `speckit.fx-to-dotnet.*` command on behalf of a `[MIG-*]` task. The hook is the sole authorized invoker of those commands for migration items. (User-story `[US*]` tasks may legitimately call non-migration commands as usual.)

</workflow>

<contracts>
- Goal 5 of the tight integration plan: only `speckit.fx-to-dotnet.*` commands run for migration items, and only via the hook. This override is the deterministic enforcement at the core-command layer.
- Ordering guarantee: Branch A ensures `[US*]` tasks NEVER execute while unresolved `[MIG-*]` tasks exist. Migration (Phase 1) always completes before user-story phases begin.
- Hook-managed: precondition gate, prerequisite deferral, dispatch validation, per-task review, build-failure pause, audit log.
</contracts>
