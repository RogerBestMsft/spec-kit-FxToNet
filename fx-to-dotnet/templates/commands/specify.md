---
description: "Generate spec.md from user story (preset override for fx-to-dotnet integration). Adds .NET Framework migration context detection to the specification."
---
# Specify Command (fx-to-dotnet-sdd preset override)

This preset overrides the core `speckit.specify` body to add .NET Framework migration awareness during specification creation. All standard specify behavior is preserved; this override adds a single post-processing step that detects Framework projects and writes a `## Migration Context` section to `spec.md`.

> **Extension-coordination directive** — This template performs lightweight, passive detection using only the `read` and `search` tools. It does NOT invoke any `speckit.fx-to-dotnet.*` extension commands, does NOT write any files under `{featureDir}/migration/`, and does NOT call MCP tools. Full classification with confidence levels, evidence, and migration artifacts is produced later by the `after_plan` hook.

<workflow>

## 1. Run core specify workflow

Execute the standard `speckit.specify` workflow in full — gather the user story, produce `spec.md`, and complete all normal specification steps. Do not alter the core behavior.

## 2. Scan for .NET Framework projects

After the core specify workflow completes, scan the workspace for solution and project files:

1. Search the workspace root for `.sln` and `.slnx` files.
2. If a solution file exists, read it and extract all referenced project paths:
   - For `.sln` (legacy text format): extract paths from `Project("{...}") = "Name", "RelativePath", "{Guid}"` lines, ignoring solution folder entries (type GUID `2150E333-8FDC-42A3-9474-1A3956D46DE8`).
   - For `.slnx` (XML format): extract every `<Project Path="..." />` element.
3. If no solution file exists, search for individual `.csproj`, `.vbproj`, and `.fsproj` files.
4. Read each discovered project file.

## 3. Check each project for Framework indicators

For each project file, check for these signals:

- `<TargetFrameworkVersion>v4.*</TargetFrameworkVersion>` → .NET Framework (legacy format)
- Root `<Project>` element has NO `Sdk` attribute AND no `<Sdk` child element → legacy project format
- `<TargetFramework>net4*</TargetFramework>` in an SDK-style project → .NET Framework
- `<TargetFrameworks>` containing any `net4*` moniker → includes .NET Framework

While reading each project file, also record these policy-relevant signals for later reporting:

- **EF6**: `<PackageReference Include="EntityFramework" …>` or `<PackageReference Include="EntityFramework.SqlServer" …>`, or `<Reference Include="System.Data.Entity" …>`
- **System.Web**: `<Reference Include="System.Web" …>`, or `<PackageReference Include="Microsoft.AspNet.Mvc" …>` / `Microsoft.AspNet.WebApi.*`
- **OWIN/Identity**: `<PackageReference Include="Microsoft.Owin" …>`, `Microsoft.Owin.*`, `Microsoft.AspNet.Identity.*`, or `<PackageReference Include="Owin" …>`
- **Windows Service**: Already captured by the `System.ServiceProcess` / `ServiceBase` check above — no additional detection needed.

These signals are advisory only — they inform the `### Applicable Policies` subsection in Step 5 but do not change classification or upgrade strategy.

If NONE of the projects target .NET Framework, stop here. Do not add any migration content to `spec.md`. The specification is complete.

## 4. Classify upgrade strategy per project

For each project that targets .NET Framework, assign a lightweight upgrade strategy classification based on observable project file signals:

| Signal | Classification | Upgrade Strategy |
|--------|---------------|-----------------|
| `Sdk="Microsoft.NET.Sdk.Web"`, or imports `Microsoft.WebApplication.targets`, or `Global.asax` / `web.config` exists in project folder | web-app-host | **side-by-side** |
| OutputType is Library AND references web frameworks (`System.Web`, `Microsoft.AspNet.Mvc`, `Microsoft.AspNet.WebApi`) but has no host artifacts (`Global.asax`, `web.config`, `Startup.cs`) | web-library | **in-place** |
| References `System.ServiceProcess` assembly or contains `ServiceBase` subclass | windows-service | **in-place** |
| OutputType is Library with no web or service indicators | class-library | **in-place** |
| OutputType is Exe with no web, service, or UI indicators | console-app | **in-place** |
| References `System.Windows.Forms` or `<UseWindowsForms>true</UseWindowsForms>` | winforms-app | **in-place** |
| References `PresentationFramework`, `WindowsBase`, or `<UseWPF>true</UseWPF>` | wpf-app | **in-place** |
| Already SDK-style with modern TFM only (net5.0+ / net6.0+ / net7.0+ / net8.0+ / net9.0+ / net10.0+, no `net4*` entry) | modern | **skip** |
| Ambiguous or conflicting signals | uncertain | **flag for confirmation** |

This is a lightweight heuristic based on project file content only. Full classification with confidence levels, evidence, dependency analysis, and MCP-backed assessment happens later during `speckit.fx-to-dotnet.assess` at plan time.

> Classifications do not imply specific migration technology choices. Policies loaded during `assess` and `plan` govern migration strategies (e.g., EF6 retention, System.Web adapters, OWIN Identity preservation).

## 5. Write Migration Context section to spec.md (idempotent)

Search `spec.md` for the heading `## Migration Context`.

- If present, **replace** the entire section body (from the `## Migration Context` heading up to but NOT including the next `## ` heading, or to end of file if no subsequent heading exists) with the current detection results. Do NOT append a duplicate.
- If absent, **append** to the end of `spec.md`.

Use this exact format:

```markdown
## Migration Context

> **Preset-managed** — this section is generated by the `fx-to-dotnet` preset's specify template. The `after_plan` hook will enrich it with full assessment data. Re-run `/speckit.specify` to refresh. Do not edit by hand.

This workspace contains .NET Framework projects that require migration to modern .NET before user-story implementation can begin.

### Projects Detected

| Project | Target Framework | Format | Classification | Upgrade Strategy |
|---------|-----------------|--------|----------------|-----------------|
| {relative path} | {e.g. net48} | {legacy or sdk-style} | {classification} | {in-place / side-by-side / skip / uncertain} |

### Upgrade Strategies

- **In-place**: Class libraries, console apps, Windows Services, web libraries, WinForms/WPF apps — multitarget to add a modern TFM alongside the Framework TFM
- **Side-by-side**: Web application hosts — create a new ASP.NET Core project alongside the legacy host and port artifacts in slices

### Applicable Policies

> The following policies were flagged based on project-file signals detected in Step 3. They will be loaded and enforced during `assess` and `plan`. See `fx-to-dotnet/policies/<name>/POLICY.md` for details.

| Policy | Signal Detected | Projects |
|--------|----------------|----------|
| {policy-id} | {signal description} | {comma-separated relative paths} |

_Only include rows where signals were actually detected. If no policy-relevant signals were found across any project, omit this entire `### Applicable Policies` subsection._

### Migration Phases

The `after_plan` hook will produce a detailed migration plan. The expected phases are:

1. SDK-Style Conversion — convert legacy `.csproj` files to SDK-style format
2. Package Compatibility Updates — update NuGet packages to versions supporting modern .NET (EF6 packages are retained per `ef6-migration-policy` — do not replace with EF Core during migration)
3. Compatible API Changes — API/pattern changes that compile on both frameworks (breadth-first, pre-multitarget)
4. Multitarget — add the modern TFM to each project (breadth-first)
5. Breaking API Changes — API changes requiring the new TFM, using `#if` conditionals (breadth-first, post-multitarget)
6. Side-by-Side Web Migration — create ASP.NET Core host and port web artifacts in slices (System.Web types use adapters per `systemweb-adapters` policy; OWIN/Identity is preserved per `owin-identity` policy)
7. Deferred Work Review & Final Validation — review unresolved items and validate the full solution build

> Migration must complete before user-story implementation begins. The `before_implement` hook enforces this gate.
```

If any project was classified as `uncertain`, append this note immediately after the `### Projects Detected` table:

```markdown
> ⚠️ One or more projects have uncertain classification. The `after_plan` hook will run full detection with MCP tools and may prompt for confirmation.
```

## 6. Continue

The specify workflow is complete. The Migration Context section is informational — it does not block specification completion and does not produce any migration state files.

</workflow>

<idempotency-rules>
- Always search for the `## Migration Context` heading before appending.
- If present, replace the entire section body; never duplicate sections.
- The `> **Preset-managed**` blockquote anchor marks the section as template-generated so other hooks and re-runs can locate it.
- Never modify content outside the `## Migration Context` section.
</idempotency-rules>
