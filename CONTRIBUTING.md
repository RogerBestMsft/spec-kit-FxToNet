# Contributing to `spec-kit-FxToNet`

Thanks for helping improve the **`fx-to-dotnet`** Spec Kit extension. This guide is for
humans; AI agents should start at [.github/copilot-instructions.md](.github/copilot-instructions.md).

## What you're working on

This repo packages one [Spec Kit](https://github.com/github/spec-kit) extension that
migrates .NET Framework apps to modern .NET, plus a companion preset
(`fx-to-dotnet-sdd`) and cross-platform tooling. There is **no application build** — the
deliverables are markdown commands/policies, YAML manifests, and paired shell/PowerShell
scripts consumed by an AI agent through the Spec Kit extension protocol.

The authoritative definition of commands, hooks, and version is
[fx-to-dotnet/extension.yml](fx-to-dotnet/extension.yml) and
[fx-to-dotnet/preset.yml](fx-to-dotnet/preset.yml). Don't rely on memory for those.

## Prerequisites

- Python 3.11 (matches CI; 3.9+ works locally)
- PowerShell 7+ for running tooling, but `.ps1` must stay **Windows PowerShell 5.1
  compatible** (see [.github/instructions/scripts.instructions.md](.github/instructions/scripts.instructions.md))
- Git, and (for the build-fix smoke tests) the .NET SDK

```pwsh
python -m venv .venv
.\.venv\Scripts\Activate.ps1            # bash: source .venv/bin/activate
python -m pip install -r tests/requirements.txt
```

## The conventions that matter

Path-scoped detail lives under [.github/instructions/](.github/instructions/):

| Area | Guide |
|------|-------|
| Commands & hooks | [command-authoring.instructions.md](.github/instructions/command-authoring.instructions.md) |
| Policies | [policies.instructions.md](.github/instructions/policies.instructions.md) |
| Scripts (parity, PS 5.1) | [scripts.instructions.md](.github/instructions/scripts.instructions.md) |
| Manifests & versioning | [manifests-versioning.instructions.md](.github/instructions/manifests-versioning.instructions.md) |
| Tests | [tests.instructions.md](.github/instructions/tests.instructions.md) |

Headline rules: one semver across `extension.yml`/`preset.yml`/`README.md`; required
command `description` frontmatter; all `speckit.fx-to-dotnet.*` references resolve; every
bash script has a PascalCase PowerShell twin; policies are loaded via
`get_instructions` and cited in a `## Policies Applied` table.

## Common changes

- **Add a command** — create `fx-to-dotnet/commands/<category>/<name>.md` with
  frontmatter, declare it under `provides.commands` in `extension.yml`, add it to both
  READMEs, and wire it under `hooks:` if it's a hook.
- **Add a policy** — create `fx-to-dotnet/policies/<id>/POLICY.md` with `name`/
  `description` frontmatter and cite it from each command that requires it.
- **Add a script** — create the bash + PowerShell twins together, declare both in
  `extension.yml`, and add a test under `tests/scripts/`.
- **Bump the version** —
  `pwsh support_scripts/bump-version.ps1 -NewVersion X.Y.Z` (or `bump-version.sh`), then
  `python support_scripts/version-check.py` and update README version lines.

## Validate before opening a PR (mirrors CI)

```pwsh
python support_scripts/version-check.py
python support_scripts/cross-reference-audit.py
pwsh support_scripts/mcp-config-validate.ps1        # or: bash support_scripts/mcp-config-validate.sh
pytest tests/structural tests/scripts
pytest tests/runtime                                # if you touched commands/hooks/orchestrator
```

If you edited any `.ps1`, parse-check it and confirm ASCII/UTF-8-BOM encoding (see the
scripts guide). CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs the same
gates on Ubuntu and Windows.

## Scope discipline

Keep changes to documentation, command/policy markdown, manifests, scripts, and tests.
Don't introduce a build system, application code, or new runtime dependencies.

## Reporting issues & triage

- File issues with one of the templates (bug report, feature request, or migration
  coverage gap). Blank issues are disabled; questions go to
  [Discussions](https://github.com/RogerBestMsft/spec-kit-FxToNet/discussions) and
  security reports go through a [private advisory](SECURITY.md).
- New issues land with `needs triage`. A maintainer adds the `type:` and `area:` labels;
  PRs are auto-labeled by path via [.github/labeler.yml](.github/labeler.yml). The label
  taxonomy lives in [.github/labels.yml](.github/labels.yml).
- Well-scoped issues may be labeled `copilot` and assigned to the GitHub Copilot coding
  agent, which opens a PR using the same gates described below.

## PR review expectations

- Every PR runs the CI gates and is reviewed by the code owner
  ([@RogerBestMsft](.github/CODEOWNERS)); Copilot may also leave an automated review.
- Complete the [pull request template](.github/pull_request_template.md) checklist and
  keep PRs focused — one logical change per PR.
- CI must be green before merge. Re-run the validate block locally if a gate fails.
