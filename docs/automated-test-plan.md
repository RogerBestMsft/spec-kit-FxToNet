# Automated Test Plan — fx-to-dotnet Extension

Status: Draft for review
Owner: TBD
Last updated: 2026-04-30

## Goals

Build a layered automated test suite for the `fx-to-dotnet` Spec Kit extension that catches regressions in:

1. **Manifests & cross-references** — `extension.yml`, `preset.yml`, workflow YAML, command frontmatter, README claims.
2. **Helper scripts** — the `scripts/` and `fx-to-dotnet/scripts/` PowerShell/Bash/Python utilities.
3. **Runtime command behavior** — orchestrator phase ordering, hook lifecycle, resume semantics, workflow execution — exercised against a mock MCP server and a synthetic .NET Framework solution.

LLM/agent reasoning steps are explicitly **out of scope** for CI; only the deterministic file-IO and MCP interactions of each command are exercised.

## Frameworks & runtime

- **pytest** — primary runner for cross-platform structural, script, and runtime tests.
- **Pester** — PowerShell-specific assertions only (param validation, error streams, `$LASTEXITCODE`).
- **GitHub Actions** — matrix over `ubuntu-latest` + `windows-latest`, on push and PR.
- Pinned dependencies via `tests/requirements.txt` (or `pyproject.toml`): `pytest`, `pyyaml`, `jsonschema`, `pytest-xdist`.

## Test layout

```
tests/
├── conftest.py                  # repo_root, parsed manifests, tmp solution fixture
├── README.md                    # how to run locally
├── requirements.txt
├── schemas/
│   ├── extension.schema.json
│   ├── preset.schema.json
│   ├── workflow.schema.json
│   └── mcp-config.schema.json
├── fixtures/
│   ├── HelloLib.csproj          # minimal SDK-style project for build script tests
│   └── fake-solution/           # 2–3 layered .csproj files for runtime tests
├── structural/                  # L1 — pure static validation
├── scripts/                     # L2 — script behavior with fixtures
├── runtime/                     # L3 — end-to-end with mock MCP
│   ├── conftest.py              # mock MCP responder + fake_solution_dir
│   └── ...
└── pester/
    └── Scripts.Tests.ps1
```

## Phase 1 — Test harness scaffolding

| # | Item |
|---|---|
| 1 | Create the directory structure above. |
| 2 | Add dependency manifest pinning `pytest`, `pyyaml`, `jsonschema`, `pytest-xdist`. |
| 3 | Author shared `tests/conftest.py` with fixtures: `repo_root`, `extension_yml`, `preset_yml`, `tmp_solution_fixture`. |
| 4 | Author `tests/README.md` with `pytest -q` and `Invoke-Pester tests/pester` instructions. |

## Phase 2 — L1: Structural validation (pytest)

All Phase 2 items are independent and run in parallel under `pytest-xdist`.

| # | File | Asserts |
|---|---|---|
| 5 | `structural/test_extension_yaml.py` | JSON-schema validity; semver `extension.version`; every `provides.commands[].file`, `scripts[]` exists; every `hooks[].command` is in `provides.commands`. |
| 6 | `structural/test_preset_yaml.py` | Schema validity; `requires.extensions[].version` constraint satisfied by current `extension.yml`; every `provides.templates[].path` exists. |
| 7 | `structural/test_workflow_yaml.py` | Discover all `commands/workflows/*/workflow.yml`; every `steps[].command` is declared; gate options non-empty; do-while has `condition` + `max_iterations`; `{{ inputs.X }}` references resolve. |
| 8 | `structural/test_command_frontmatter.py` | Every `commands/**/*.md` parses; `description` present; `tools` is a list; referenced commands/scripts resolve. |
| 9 | `structural/test_cross_references.py` | Wraps `scripts/cross-reference-audit.py` via subprocess (exit 0); also re-implements scan to snapshot resolved/unresolved sets. |
| 10 | `structural/test_policy_links.py` | Grep command bodies for `policies/*.md` and `policies/**/POLICY.md`; assert each target exists. |
| 11 | `structural/test_readme_claims.py` | README command/hook tables match `extension.yml` (catches drift like the known-stale `docs/workflow-plan.md`). |
| 12 | `structural/test_version_consistency.py` | Wraps `scripts/version-check.py` (exit 0). |
| 13 | `structural/test_mcp_config.py` | Extract JSON block from `fx-to-dotnet/policies/mcp-setup.md`; validate against schema; also runs `mcp-config-validate.ps1` and `.sh` as subprocesses. |

## Phase 3 — L2: Script behavior with fixtures

Runs alongside Phase 2.

| # | File | Asserts |
|---|---|---|
| 14 | `scripts/test_dotnet_build_scripts.py` | Both `dotnet-build.sh` and `dotnet-build.ps1` run against `tests/fixtures/HelloLib.csproj`; output contains `::build-start::`, `::build-end::`, `exit-code:`; exit code propagated. Skip bash on bare Windows. |
| 15 | `scripts/test_bump_version.py` | Copy `extension.yml` to tmp; run `bump-version.{ps1,sh} 9.9.9`; assert update; assert semver rejection on `abc`. |
| 16 | `scripts/test_package_extensions.py` | Run packager into tmp; assert `releases/fx-to-dotnet-{ver}.zip` exists and contains `extension.yml` + at least one command file. |
| 17 | `scripts/test_generate_catalog.py` | Run both `.py` and `.ps1`; parse JSON; assert required keys (`id`, `version`, `tags`, …). |
| 18 | `scripts/test_script_pairs_parity.py` | For each `(*.ps1, *.sh|*.py)` pair, run with same input and diff normalized stdout. Catches drift like the existing semver-check inconsistency. |
| 19 | `pester/Scripts.Tests.ps1` | Pester assertions for PS-only details: parameter validation, error streams, `$LASTEXITCODE`. |

## Phase 4 — L3: Runtime / end-to-end (pytest)

| # | File | Asserts |
|---|---|---|
| 20 | `runtime/conftest.py` | Hand-rolled **mock MCP server** (stdio JSON-RPC) impersonating `Microsoft.GitHubCopilot.Modernization.Mcp` + `Swick.Mcp.Fx2dotnet`; canned responses for `get_state`, `get_projects_in_topological_order`, `convert_project_to_sdk_style`, `FindRecommendedPackageUpgrades`, `ComputeDependencyLayers`, etc. Also a `fake_solution_dir` fixture with 2–3 minimal `.csproj` files arranged in a layered dependency graph. |
| 21 | `runtime/test_assess_command_smoke.py` | Thin command-driver parses `commands/assess/assess.md`, executes deterministic file-IO + MCP steps; asserts `analysis.md` and `package-updates.md` produced with expected sections. |
| 22 | `runtime/test_orchestrator_phase_order.py` | Drive `commands/orchestrate/orchestrate.md`; inspect `plan.md` mutations to verify documented 7-phase order. |
| 23 | `runtime/test_resume_semantics.py` | Pre-seed `plan.md` with `lastCompletedPhase: assess`; rerun driver; assert assess is skipped. |
| 24 | `runtime/test_hook_lifecycle.py` | Simulate `after_specify → after_plan → after_tasks → before_implement → after_implement`; mandatory hooks fail-loud, optional hooks silent-exit. |
| 25 | `runtime/test_workflow_executor.py` | Minimal interpreter for `workflow.yml` (gate / do-while / command); run `assess-and-plan` and `sdk-normalize` against mock MCP; assert step outputs and gate prompts. |

## Phase 5 — CI integration

| # | Item |
|---|---|
| 26 | `.github/workflows/test.yml` — matrix `{ubuntu-latest, windows-latest}` with jobs: `lint` (yamllint + jsonschema), `test-structural` (`pytest tests/structural -n auto`), `test-scripts` (`pytest tests/scripts -n auto` + `Invoke-Pester tests/pester -CI`), `test-runtime` (`pytest tests/runtime -n auto`). Upload junit + coverage artifacts. |
| 27 | `.github/workflows/release.yml` — on tag, full suite then `package-extensions.{ps1,sh}` attaching zips to the release. |
| 28 | `.github/dependabot.yml` — `pip` + `github-actions` ecosystems. |

## Relevant files

- [fx-to-dotnet/extension.yml](../fx-to-dotnet/extension.yml) — source of truth for declared commands/hooks/scripts.
- [presets/fx-to-dotnet-sdd/preset.yml](../presets/fx-to-dotnet-sdd/preset.yml) — preset version coupling.
- `fx-to-dotnet/commands/**/*.md` — frontmatter + cross-reference targets.
- `fx-to-dotnet/commands/workflows/*/workflow.yml` — schema + executor input.
- [fx-to-dotnet/policies/mcp-setup.md](../fx-to-dotnet/policies/mcp-setup.md) — MCP JSON snippet.
- [fx-to-dotnet/scripts/bash/dotnet-build.sh](../fx-to-dotnet/scripts/bash/dotnet-build.sh), [fx-to-dotnet/scripts/powershell/dotnet-build.ps1](../fx-to-dotnet/scripts/powershell/dotnet-build.ps1) — runtime scripts under test.
- All `scripts/` helpers — wrapped via subprocess assertions; any pair drift surfaced gets fixed.
- `policies/**/POLICY.md`, `fx-to-dotnet/policies/*.md` — link-check targets.
- [README.md](../README.md), [docs/workflow-plan.md](workflow-plan.md) — claim-validation targets (workflow-plan.md is known-stale; tests will catch it).

## Verification

1. `pytest -q tests/structural` is green. Deliberately renaming a command file makes `test_cross_references` fail.
2. `pytest -q tests/scripts` runs on Windows + Linux; parity diff is empty.
3. `Invoke-Pester tests/pester -Output Detailed` is green on Windows.
4. `pytest -q tests/runtime` — mock MCP responds; expected outputs produced; phase order asserted.
5. GitHub Actions matrix on a feature branch is green; junit artifacts uploaded.
6. **Mutation matrix** — five deliberate defects each fail exactly the expected test, no collateral:
   - Delete a command file → `test_extension_yaml` / `test_cross_references`.
   - Mismatch preset version → `test_preset_yaml`.
   - Break a `steps[].command` name → `test_workflow_yaml`.
   - Malform `mcp-setup.md` JSON → `test_mcp_config`.
   - Bump only one extension version (when more are added) → `test_version_consistency`.
7. Suite budget < 3 min per OS.

## Decisions

- **Scope:** full, including runtime MCP/agent flow.
- **Frameworks:** pytest cross-platform + Pester for PS-only assertions.
- **CI:** GitHub Actions, push + PR, Windows + Linux matrix.
- **Agent reasoning:** not executed in CI; only deterministic file-IO + MCP interactions, with a hand-rolled mock MCP responder.
- **Out of scope:** real migrations, live NuGet calls, live `dnx` MCP package downloads.

## Open questions

1. **Mock MCP fidelity** — hand-rolled stubs (recommended start) vs record/replay of real MCP traffic (deferred until drift hurts)?
2. **.NET SDK in CI** — install .NET 10 preview via `global.json` (slow but accurate) or use `net8.0` fixtures for build-script tests plus a separate nightly job on the real preview SDK (recommended)?
3. **Pester scope** — PS-specific assertions only (recommended) or full mirror of pytest scripts (two sources of truth)?

## Suggested execution order

1. Phase 1 (scaffolding) → Phase 2 (structural) — fastest feedback, smallest blast radius.
2. Phase 3 (scripts) — surfaces and fixes any pair drift.
3. Phase 5 step 26 (CI for L1+L2) — get green CI before runtime work.
4. Phase 4 (runtime) — most complex; mock MCP design lives or dies here.
5. Phase 5 steps 27–28 — release + dependabot polish.
