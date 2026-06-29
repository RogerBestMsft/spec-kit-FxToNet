# Copilot instructions — `spec-kit-FxToNet`

Always-on guidance for updating this repository. This is the **canonical** agent doc;
[AGENTS.md](../AGENTS.md) is a thin pointer to it, and the files under
[.github/instructions/](instructions/) carry deeper, path-scoped rules that load only
when you touch the matching files.

> **Source of truth.** Never hardcode the version, command list, or hook list from
> memory. Read [fx-to-dotnet/extension.yml](../fx-to-dotnet/extension.yml) and
> [fx-to-dotnet/preset.yml](../fx-to-dotnet/preset.yml) — they define everything the
> tests enforce.

## What this repo is

`spec-kit-FxToNet` packages a single [GitHub Spec Kit](https://github.com/github/spec-kit)
extension, **`fx-to-dotnet`**, that orchestrates migrating .NET Framework apps to modern
.NET (default `net10.0`), plus a companion preset (`fx-to-dotnet-sdd`) and cross-platform
tooling. It is **not** a Python app; the deliverable is markdown commands/policies +
YAML manifests + shell/PowerShell helpers, all consumed by an AI agent through the Spec
Kit extension protocol.

Spec Kit's relevant concepts:

- **Spec-Driven Development lifecycle**: `/speckit.specify` → `/speckit.plan` →
  `/speckit.tasks` → `/speckit.implement`.
- **Extension** = adds new commands/templates. **Preset** = overrides core templates.
- **Hooks** fire at lifecycle points (`after_specify`, `after_plan`, `after_tasks`,
  `before_implement`, `after_implement`).

## Architecture (read the manifest for exact counts)

```
fx-to-dotnet/
  extension.yml      # commands, hooks, requires, tags, version — THE manifest
  preset.yml         # fx-to-dotnet-sdd; overrides core tasks/implement/plan templates
  commands/          # one markdown file per command (core commands + 5 hooks)
  policies/          # one folder per domain policy (POLICY.md + optional references/)
  scripts/{bash,powershell}/   # paired helper scripts declared in extension.yml
  templates/         # preset template overrides
support_scripts/     # version-check, cross-reference-audit, bump-version, package, deploy, catalog (ps1/sh/py)
tests/               # structural / scripts / runtime / schemas
.github/workflows/   # ci.yml (validation gates), release.yml, community-catalog-pr.yml
```

**Commands** are the agent-facing "instructions": each is a markdown file with YAML
frontmatter (`description`, optional `tools`/`commands`/`handoffs`/`scripts`) plus a body
describing workflow, constraints, required policies, and state-file conventions.

**Hooks** (declared under `hooks:` in the manifest) map a lifecycle event to a command.
All hooks are mandatory (`optional: false`) **except** `after_implement`/`verify-hook`.
The `before_implement` hook (`implement-hook`) is **THE GATE**: it blocks
`/speckit.implement` until every `[MIG-*]` task is resolved, and it is the only place
that interprets `[MIG-*]` `dispatch:` trailers. Dispatch targets are validated against
`^speckit\.fx-to-dotnet\.[a-z0-9-]+$`. Mandatory hooks **silent-exit success** on
non-Framework workspaces.

**Migration artifacts** live per-feature under `{featureDir}/migration/` where
`{featureDir}` = `specs/<branch>/` (resolved from `SPECIFY_FEATURE` or the git branch).
Examples: `analysis.md` (owner: `assess`), `plan.md` (owner: `plan`),
`orchestration.md` (owner: `orchestrate`/`initialize`), `package-updates.md` (dual
ownership: `assess` findings + `update-packages` execution state), per-project
`{ProjectName}.md`.

## Golden rules — what the test suite enforces

These invariants will fail CI if broken. Honor them in every change.

1. **Single version everywhere.** `extension.yml`, `preset.yml`, and `README.md` must
   declare the **same** semver. The preset's
   `requires.extensions[].version` constraint (e.g. `>=X.Y.Z`) must be satisfied by the
   extension version. Bump with `support_scripts/bump-version.*`, never by hand-editing
   one file. (`tests/structural/test_version_consistency.py`,
   `test_preset_yaml.py`, `test_readme_claims.py`)
2. **Command frontmatter contract.** Every `commands/**/*.md` needs YAML frontmatter
   with a non-empty `description`. `tools` (if present) must be a list. Any
   `speckit.fx-to-dotnet.*` reference in `commands`/`handoffs` must resolve to a command
   declared in `extension.yml`. (`test_command_frontmatter.py`)
3. **Cross-references resolve.** Every `speckit.fx-to-dotnet.*` mention anywhere in
   `commands/**` must be a declared command. Run
   `python support_scripts/cross-reference-audit.py`. (`test_cross_references.py`)
4. **Script parity.** Every `scripts/bash/<kebab>.sh` has a PascalCase PowerShell twin
   `scripts/powershell/<Pascal>.ps1` implementing identical behavior, and both are listed
   in the command's `scripts:` array. (`tests/scripts/test_script_pairs_parity.py`)
5. **PowerShell 5.1 compatibility.** All `.ps1` must run under Windows PowerShell 5.1:
   ASCII or UTF-8-with-BOM encoding; no `??`, `?:`, or `ConvertFrom-Json -AsHashtable`.
   See [scripts instructions](instructions/scripts.instructions.md).
6. **Policy proof.** A command that requires a policy must load it via
   `get_instructions(kind='policy', query='<policy-id>')` and emit a `## Policies Applied`
   table row (even when no code matches: `Applied To = none — no matches`,
   `Outcome = n/a`). The `after_plan` hook blocks `/speckit.plan` if a required policy is
   uncited.
7. **MCP config snippets.** `policies/mcp-setup.md` must keep both `servers` (VS Code)
   and `mcpServers` (other hosts) JSON variants valid and include the
   `Microsoft.GitHubCopilot.Modernization.Mcp` entry. (`test_mcp_config.py`)
8. **CHANGELOG marker.** `CHANGELOG.md` starts with `# Changelog` and keeps the
   `<!-- RELEASES -->` marker — the release workflow inserts entries there.
   (`test_changelog.py`)

## How to make common changes

### Add / rename a command
1. Create `commands/<category>/<name>.md` with frontmatter (`description` required).
2. Declare it under `provides.commands` in `extension.yml` (`name` + `file`, plus
   `scripts:` if it uses helpers). Use the `speckit.fx-to-dotnet.<name>` namespace.
3. If it's a hook, also wire it under `hooks:` with `optional:` and `description:`.
4. Add it to the command table in `README.md` and `fx-to-dotnet/README.md`.
5. Update any cross-references; run the validation commands below.

### Add a policy
Create `policies/<id>/POLICY.md` with frontmatter (`name`, `description`). Cite it from
the commands that require it and add the `get_instructions` mandatory-load line. See
[policies instructions](instructions/policies.instructions.md).

### Add a script
Create the bash and PowerShell twin together, declare both in `extension.yml`, and add a
behavior test under `tests/scripts/`. See
[scripts instructions](instructions/scripts.instructions.md).

### Bump the version
```pwsh
pwsh support_scripts/bump-version.ps1 -NewVersion X.Y.Z   # or bump-version.sh X.Y.Z
python support_scripts/version-check.py
```
Then update the version lines in `README.md` and, if the lower bound changed, the
preset's `requires.extensions[].version`.

## Validate before you finish

Mirror the CI gates in [.github/workflows/ci.yml](workflows/ci.yml):

```pwsh
python -m pip install -r tests/requirements.txt
python support_scripts/version-check.py
python support_scripts/cross-reference-audit.py
pwsh support_scripts/mcp-config-validate.ps1        # or: bash support_scripts/mcp-config-validate.sh
pytest tests/structural tests/scripts
pytest tests/runtime                                # if you touched commands/hooks/orchestrator
```

If you edited any `.ps1`, parse-check it (see scripts instructions) and confirm encoding.

## Scope discipline

Documentation, command/policy markdown, manifests, scripts, and tests only. Do not
introduce a build system, app code, or new dependencies. Keep changes minimal and aligned
with the conventions above; when in doubt, read the relevant
[.github/instructions/](instructions/) file and the JSON schemas under
[tests/schemas/](../tests/schemas/).
