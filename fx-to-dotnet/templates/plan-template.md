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

### Migration Content Boundaries

When `## Migration Context Detected` exists in `spec.md` and lists .NET Framework projects:

- **Do NOT** generate a "Technical Context" table with "Current State → Target State" columns for migration-scoped technologies (ORM, identity provider, DI container, web framework, background services, logging stack). These decisions are owned by the extension's migration plan.
- **Do NOT** prescribe specific replacement technologies (e.g., "EF6 → EF Core", "IdentityServer3 → Duende") in plan phases, summaries, or design sections.
- **Do NOT** generate migration phases that overlap with the extension-managed phases (SDK conversion, package updates, multitarget, web migration, build verification, deferred work).
- **DO** reference the `### Migration Policy Constraints` subsection in `spec.md` and respect every constraint listed there.
- **DO** defer all migration technology decisions to the `## .NET Migration Plan` extension-managed section and the `{featureDir}/migration/plan.md` artifact.
- **DO** focus the core plan on user-story functionality, architecture, and non-migration concerns.

Content generated outside `> **Extension-managed**` blockquotes that contradicts these boundaries will be flagged and corrected by the `after_plan` hook.

---

<!-- Remainder of the core plan template (Phases, Constitution alignment, etc.) follows unchanged. -->
