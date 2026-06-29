---
applyTo: "fx-to-dotnet/commands/**/*.md"
description: "Authoring rules for fx-to-dotnet command and hook markdown files: frontmatter contract, body conventions, policy proof, state-file paths, hook idempotency and the implement gate."
---

# Command & hook authoring (`fx-to-dotnet/commands/**`)

Each command is a markdown file: **YAML frontmatter** + a body the agent executes. The
file is referenced from `provides.commands[].file` in
[extension.yml](../../fx-to-dotnet/extension.yml). Enforced by
`tests/structural/test_command_frontmatter.py` and `test_cross_references.py`.

## Frontmatter contract

```yaml
---
description: "Non-empty one-line summary"          # REQUIRED
tools: [read, search, edit, ask-questions, invoke-command]   # if present, MUST be a list
commands:                                          # optional sub-commands this invokes
  - "speckit.fx-to-dotnet.detect"
handoffs:                                          # optional
  - label: "Generate Migration Plan"
    agent: speckit.fx-to-dotnet.plan
    prompt: "…uses {featureDir}/migration/analysis.md"
    send: true
scripts:                                           # optional; must match extension.yml
  - "scripts/bash/find-recommended-package-upgrades.sh"
  - "scripts/powershell/Find-RecommendedPackageUpgrades.ps1"
---
```

Rules:
- `description` is required and must be non-empty.
- `tools`, if present, must be a YAML **list**. MCP tools use the
  `microsoft.githubcopilot.modernization.mcp/*` form.
- Every `speckit.fx-to-dotnet.*` value in `commands:` and every `handoffs[].agent` must
  resolve to a command declared in `extension.yml`. Same for any `speckit.fx-to-dotnet.*`
  mention in the **body** — the cross-reference audit scans the whole file.
- If you add `scripts:` here, list the **same** paths under that command in
  `extension.yml`, and include both the bash and PowerShell twins.

## Body conventions

- Open with a role/identity sentence ("You are a .NET migration … specialist.").
- Use a `<state-file-conventions>` block to define `{featureDir}` (`specs/<branch>/`,
  resolved from `SPECIFY_FEATURE` or git branch), `{solutionDir}`, `{ProjectName}`, and
  the **output files** under `{featureDir}/migration/`.
- **File existence checks use the `read` tool**, never shell (`Test-Path`, `Get-Item`).
  Use `edit` to create/update state files.
- Add a `## Constraints` section listing what the command must NOT do (e.g. assessment
  must not change code).

## Policy proof (required-policy commands)

If the command depends on domain policies:
- Add a `## Required Policies` section with one `⛔ MANDATORY: Call
  get_instructions(kind='policy', query='<policy-id>')` line per policy.
- State that each loaded policy MUST appear as a row in a `## Policies Applied` table in
  the command's output artifact. Policies with no matching code still emit a row:
  `Applied To = none — no matches`, `Outcome = n/a`. The row presence is the proof.
- The `after_plan` hook blocks `/speckit.plan` if a required policy is uncited.

## Hooks

Hook files live in `commands/hooks/` and are wired under `hooks:` in `extension.yml`.

- **Idempotent edits.** Re-running a hook must not duplicate content. Anchor edits with a
  stable heading (e.g. `## Migration Context Detected`) or a
  `> **Extension-managed**` blockquote, and update in place if the anchor exists.
- **Silent-exit success** when no `{featureDir}` is detectable or no .NET Framework
  projects are present — mandatory hooks must never block ordinary Spec Kit usage.
- `implement-hook` is **THE GATE** (`before_implement`): it verifies preconditions
  (`analysis.md`, `plan.md`, `[MIG-*]` rows), executes each unchecked `[MIG-*]` with
  per-task review, and is the **only** place that interprets `dispatch:` trailers. Every
  dispatch target is validated against `^speckit\.fx-to-dotnet\.[a-z0-9-]+$` before
  invocation. Build failures always pause, even under `autoApprove-rest`.

After editing any command/hook, run
`python support_scripts/cross-reference-audit.py` and
`pytest tests/structural` (and `tests/runtime` if you changed the orchestrator or hooks).
