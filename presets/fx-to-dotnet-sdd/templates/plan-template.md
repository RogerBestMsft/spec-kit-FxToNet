# Plan Template (fx-to-dotnet-sdd preset override)

This template overrides the core `templates/plan-template.md` to add a Migration Gate inside the Constitution Check for solutions that contain .NET Framework projects.

---

## Constitution Check

<!-- Core constitution check items remain here; this preset adds the Migration Gate subsection below. -->

### Migration Gate (fx-to-dotnet)

This subsection applies when `.specify/extensions.yml` enables `fx-to-dotnet` AND the workspace contains at least one .NET Framework project (per `{featureDir}/migration/detection.md`).

Before `speckit.implement` may run, the following artifacts MUST exist (the `before_implement` hook is the failsafe, but the Constitution Check surfaces the requirement up-front):

| Artifact | Owner | Purpose |
|---|---|---|
| `{featureDir}/migration/analysis.md` | `speckit.fx-to-dotnet.assess` (via `after_plan` hook) | Migration assessment, evidence, policy citations (shared artifact under the active Spec Kit feature folder) |
| `{featureDir}/migration/plan.md` | `speckit.fx-to-dotnet.plan` (via `after_plan` hook) | Phase ordering, dispatch units, target frameworks (shared artifact under the active Spec Kit feature folder) |
| `[MIG-*]` rows in `tasks.md` | `after_tasks` hook | Granular dispatch units with `dispatch:` trailers |
| `## .NET Migration Plan` section in `plan.md` | `after_plan` hook | Extension-managed plan summary |

**Gate criteria**:

- [ ] All four artifacts above are present.
- [ ] Every `[MIG-*]` row has a `dispatch:` trailer matching `^speckit\.fx-to-dotnet\.[a-z0-9-]+\(.*\)$`.
- [ ] The `## .NET Migration Plan` section is wrapped in a `> **Extension-managed**` blockquote (idempotency anchor).
- [ ] No competing migration content appears outside extension-managed sections.

If any gate criterion fails, the `before_implement` hook will block `speckit.implement` with a remediation message. Resolve the failing item and re-run `/speckit.plan` and/or `/speckit.tasks` to regenerate the missing artifact.

---

<!-- Remainder of the core plan template (Phases, Constitution alignment, etc.) follows unchanged. -->
