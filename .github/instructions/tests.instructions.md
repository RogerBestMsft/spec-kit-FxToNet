---
applyTo: "tests/**"
description: "How the fx-to-dotnet test suite is organized (structural/scripts/runtime/schemas), which invariant each structural test guards, and how to run the suite locally to mirror CI."
---

# Tests (`tests/**`)

The suite is the executable spec for the repo's conventions. Requires Python 3.11 in CI
(3.9+ locally per `tests/README.md`); deps in `tests/requirements.txt` (`pytest`,
`pyyaml`, `jsonschema`, `pytest-xdist`).

## Layout

| Dir | Level | What it checks |
|-----|-------|----------------|
| `structural/` | L1 static | manifests, frontmatter, cross-references, version, README, MCP config, changelog |
| `scripts/` | L2 behavior | `support_scripts/` and `fx-to-dotnet/scripts/` helpers (pytest + Pester `Scripts.Tests.ps1`) |
| `runtime/` | L3 e2e | orchestrator phase order, hook lifecycle, resume semantics, mock MCP |
| `schemas/` | — | JSON schemas for `extension.yml`, `preset.yml`, MCP config |
| `fixtures/` | — | minimal SDK csproj + a small layered fake solution |

## What each structural test guards

- `test_extension_yaml.py` — schema valid; semver; declared command files & scripts
  exist; hook commands declared; unique names.
- `test_preset_yaml.py` — schema valid; preset version satisfies the extension-version
  constraint; template paths exist.
- `test_command_frontmatter.py` — every command `.md` has frontmatter with non-empty
  `description`; `tools` is a list; command/handoff refs resolve.
- `test_cross_references.py` — runs `cross-reference-audit.py`; all
  `speckit.fx-to-dotnet.*` mentions resolve.
- `test_version_consistency.py` — runs `version-check.py`; manifests agree.
- `test_readme_claims.py` — README command tables cite only declared commands; version
  lines match.
- `test_mcp_config.py` — both JSON variants in `mcp-setup.md` validate; required MCP
  server present; runs the `mcp-config-validate` scripts.
- `test_changelog.py` — `# Changelog` header + `<!-- RELEASES -->` marker present.
- `test_policy_links.py` — policy folder references in commands resolve.
- `test_workflow_actions.py` — every `uses:` in `.github/workflows/**` is a local
  workflow or a GitHub/Microsoft-owned action (`actions`/`github`/`microsoft`/`azure`)
  pinned to a full 40-char commit SHA; no third-party actions or floating tags.

## Running locally (mirrors `.github/workflows/ci.yml`)

```pwsh
python -m pip install -r tests/requirements.txt
pytest tests/structural tests/scripts -n auto --maxfail=1
pytest tests/runtime -n auto                # if you touched commands/hooks/orchestrator
```

## When adding tests

- Use the shared fixtures in `tests/conftest.py` (`repo_root`, `extension_dir`,
  `extension_yml`, etc.) rather than re-parsing files.
- New helper script → add a behavior test under `tests/scripts/` (and Pester coverage in
  `Scripts.Tests.ps1` for `.ps1`).
- Keep the semver regex and schema expectations aligned with `tests/schemas/`.

## Reviewing a PR (incl. Copilot review)

Green CI alone is not sufficient — it only runs the *existing* suite. When reviewing,
flag any change that adds untested behavior:

- A new or renamed helper script with **no** matching `tests/scripts/` test (and no Pester
  case in `Scripts.Tests.ps1` for the `.ps1` twin).
- A new command or hook with **no** `tests/runtime/` coverage.
- A new structural invariant or convention with **no** `tests/structural/` guard.

Request the missing test, or an explicit rationale in the PR for why none is needed.
