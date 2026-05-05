# Automated Test Plan — fx-to-dotnet Extension

Status: Approved — Ready for Implementation
Owner: TBD
Last updated: 2026-05-01

## Goals

Build a layered automated test suite for the `fx-to-dotnet` Spec Kit extension that catches regressions in:

1. **Manifests & cross-references** — `extension.yml`, `preset.yml`, command frontmatter, README claims.
2. **Helper scripts** — the `scripts/` and `fx-to-dotnet/scripts/` PowerShell/Bash/Python utilities.
3. **Runtime command behavior** — orchestrator phase ordering, hook lifecycle, resume semantics — exercised against a mock MCP server and a synthetic .NET Framework solution.

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
| 8 | `structural/test_command_frontmatter.py` | Every `commands/**/*.md` parses; `description` present; `tools` is a list; referenced commands/scripts resolve. |
| 9 | `structural/test_cross_references.py` | Wraps `scripts/cross-reference-audit.py` via subprocess (exit 0); also re-implements scan to snapshot resolved/unresolved sets. |
| 10 | `structural/test_policy_links.py` | Grep command bodies for `policies/*.md` and `policies/**/POLICY.md`; assert each target exists. |
| 11 | `structural/test_readme_claims.py` | README command/hook tables match `extension.yml`. |
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

## Phase 5 — CI integration

| # | Item |
|---|---|
| 26 | `.github/workflows/test.yml` — matrix `{ubuntu-latest, windows-latest}` with jobs: `lint` (yamllint + jsonschema), `test-structural` (`pytest tests/structural -n auto`), `test-scripts` (`pytest tests/scripts -n auto` + `Invoke-Pester tests/pester -CI`), `test-runtime` (`pytest tests/runtime -n auto`). Upload junit + coverage artifacts. |
| 27 | `.github/workflows/release.yml` — on tag, full suite then `package-extensions.{ps1,sh}` attaching zips to the release. |
| 28 | `.github/dependabot.yml` — `pip` + `github-actions` ecosystems. |

## Relevant files

- [fx-to-dotnet/extension.yml](../fx-to-dotnet/extension.yml) — source of truth for declared commands/hooks/scripts.
- [fx-to-dotnet/preset.yml](../fx-to-dotnet/preset.yml) — preset version coupling.
- `fx-to-dotnet/commands/**/*.md` — frontmatter + cross-reference targets.
- [fx-to-dotnet/policies/mcp-setup.md](../fx-to-dotnet/policies/mcp-setup.md) — MCP JSON snippet.
- [fx-to-dotnet/scripts/bash/dotnet-build.sh](../fx-to-dotnet/scripts/bash/dotnet-build.sh), [fx-to-dotnet/scripts/powershell/dotnet-build.ps1](../fx-to-dotnet/scripts/powershell/dotnet-build.ps1) — runtime scripts under test.
- All `scripts/` helpers — wrapped via subprocess assertions; any pair drift surfaced gets fixed.
- `policies/**/POLICY.md`, `fx-to-dotnet/policies/*.md` — link-check targets.
- [README.md](../README.md) — claim-validation target.

## Verification

1. `pytest -q tests/structural` is green. Deliberately renaming a command file makes `test_cross_references` fail.
2. `pytest -q tests/scripts` runs on Windows + Linux; parity diff is empty.
3. `Invoke-Pester tests/pester -Output Detailed` is green on Windows.
4. `pytest -q tests/runtime` — mock MCP responds; expected outputs produced; phase order asserted.
5. GitHub Actions matrix on a feature branch is green; junit artifacts uploaded.
6. **Mutation matrix** — five deliberate defects each fail exactly the expected test, no collateral:
   - Delete a command file → `test_extension_yaml` / `test_cross_references`.
   - Mismatch preset version → `test_preset_yaml`.
   - Malform `mcp-setup.md` JSON → `test_mcp_config`.
   - Bump only one extension version (when more are added) → `test_version_consistency`.
7. Suite budget < 3 min per OS.

## Decisions

- **Scope:** full, including runtime MCP/agent flow (L1 + L2 + L3 + CI + nightly).
- **Frameworks:** pytest cross-platform + Pester 5 for PS-only assertions (param validation, error streams, `$LASTEXITCODE`). Pytest is the sole source of truth for cross-platform script behavior.
- **CI:** GitHub Actions, push + PR, Windows + Linux matrix; nightly job for .NET 10 preview SDK.
- **Mock MCP:** hand-rolled stdio JSON-RPC stub responder; record/replay deferred until drift hurts.
- **.NET SDK in CI:** PR jobs use `net8.0` fixtures (fast, broadly available); nightly installs .NET 10 preview via `global.json` and runs `tests/scripts` + `tests/runtime` against a `tests/fixtures/fake-solution-net10/` fixture set.
- **Agent reasoning:** not executed in CI; only deterministic file-IO + MCP interactions exercised.
- **Out of scope:** real customer migrations, live NuGet calls, live `dnx` MCP package downloads, LLM/agent reasoning execution.

## PR strategy

- **PR #1**: Phases 1–3 + CI step 26 (L1 + L2 with green CI). Smallest blast radius, fastest feedback.
- **PR #2**: Phase 4 (L3 runtime/mock-MCP) + Phase 5 steps 27–28 (release + dependabot polish) + nightly workflow.

## Suggested execution order

1. Phase 1 (scaffolding) → Phase 2 (structural) — fastest feedback.
2. Phase 3 (scripts) — surfaces and fixes any pair drift.
3. Phase 5 step 26 (CI for L1+L2) — get green CI before runtime work.
4. Phase 4 (runtime) — most complex; mock MCP design lives or dies here.
5. Phase 5 steps 27–28 + nightly workflow — release polish + .NET 10 preview gating.

## Task list

Task IDs are stable across phases; `[P]` denotes tasks safe to run in parallel within a phase. Each task lists the files it touches and the acceptance signal that proves it is done.

### Phase 1 — Harness scaffolding (blocks all)

- **T001** Create `tests/{schemas,fixtures,structural,scripts,runtime}/` directory tree.
  - *Done when*: directories exist and are tracked.
- **T002 [P]** Author `tests/requirements.txt` pinning `pytest>=8`, `pyyaml>=6`, `jsonschema>=4`, `pytest-xdist>=3`.
  - *Done when*: `pip install -r tests/requirements.txt` succeeds on a clean venv.
- **T003 [P]** Author `tests/conftest.py` exposing `repo_root`, `extension_yml`, `preset_yml`, `tmp_solution_fixture`.
  - *Done when*: a smoke test consuming each fixture passes.
- **T004 [P]** Author `tests/README.md` documenting `pytest -q`, `pytest -n auto`, and `Invoke-Pester tests/scripts/Scripts.Tests.ps1`.
  - *Done when*: file present; commands work locally.
- **T005 [P]** Author JSON schemas under `tests/schemas/`: `extension.schema.json`, `preset.schema.json`, `mcp-config.schema.json`.
  - *Done when*: validating each live manifest against its schema returns zero errors.
- **T006 [P]** Author `tests/fixtures/HelloLib.csproj` — minimal SDK-style `net8.0` library + one `Class1.cs`.
  - *Done when*: `dotnet build` succeeds locally.
- **T007 [P]** Author `tests/fixtures/fake-solution/` — 2–3 layered `net8.0` csprojs + `.sln`.
  - *Done when*: `dotnet build` succeeds; topo order is unambiguous.

### Phase 2 — L1 Structural tests (parallel after Phase 1)

- **T008 [P]** `tests/structural/test_extension_yaml.py` — schema validity; semver; every `provides.commands[].file` and `scripts[]` resolves; every `hooks[].command` is declared.
- **T009 [P]** `tests/structural/test_preset_yaml.py` — schema; preset version constraint matches current `extension.yml`; templates resolve.
- **T011 [P]** `tests/structural/test_command_frontmatter.py` — frontmatter parses; `description` present; `tools` is list; cross-refs resolve.
- **T012 [P]** `tests/structural/test_cross_references.py` — wraps `support_scripts/cross-reference-audit.py` + snapshot of resolved/unresolved sets.
- **T013 [P]** `tests/structural/test_policy_links.py` — `policies/*.md` and `policies/**/POLICY.md` targets exist.
- **T014 [P]** `tests/structural/test_readme_claims.py` — README ↔ `extension.yml` drift check.
- **T015 [P]** `tests/structural/test_version_consistency.py` — wraps `support_scripts/version-check.py`.
- **T016 [P]** `tests/structural/test_mcp_config.py` — JSON in `mcp-setup.md` + validate scripts.

### Phase 3 — L2 Script tests (parallel with Phase 2)

- **T018 [P]** `tests/scripts/test_dotnet_build_scripts.py` — `::build-start::`, `::build-end::`, `exit-code:` markers + propagation; skip bash on bare Windows.
- **T019 [P]** `tests/scripts/test_bump_version.py` — copy `extension.yml`; run `bump-version.{ps1,sh} 9.9.9`; reject `abc`.
- **T020 [P]** `tests/scripts/test_package_extensions.py` — bundle layout matches the smoke-pack assertions in [.github/workflows/ci.yml](../.github/workflows/ci.yml).
- **T021 [P]** `tests/scripts/test_generate_catalog.py` — JSON keys (`id`, `version`, `tags`, …) from both `.py` and `.ps1`.
- **T022 [P]** `tests/scripts/test_script_pairs_parity.py` — diff normalized stdout across `(*.ps1, *.sh|*.py)` pairs under `support_scripts/`.
- **T023 [P]** `tests/scripts/Scripts.Tests.ps1` — Pester 5 PS-only assertions.

### Phase 4 — L3 Runtime / mock MCP (depends on Phases 2–3 + CI green)

- **T024** `tests/runtime/conftest.py` — stdio JSON-RPC mock MCP responder for `Microsoft.GitHubCopilot.Modernization.Mcp` + `Swick.Mcp.Fx2dotnet`; canned `get_state`, `get_projects_in_topological_order`, `convert_project_to_sdk_style`, `FindRecommendedPackageUpgrades`, `ComputeDependencyLayers`; `fake_solution_dir` fixture.
- **T025** `tests/runtime/_driver.py` — thin command-driver that parses a command's `commands/**/*.md` and executes only its deterministic file-IO + MCP-call steps (LLM reasoning stubbed).
- **T026 [P]** `tests/runtime/test_assess_command_smoke.py` — `analysis.md` + `package-updates.md` produced with expected sections.
- **T027 [P]** `tests/runtime/test_orchestrator_phase_order.py` — 7-phase order in `plan.md`.
- **T028 [P]** `tests/runtime/test_resume_semantics.py` — pre-seed `lastCompletedPhase: assess`; assess phase skipped.
- **T029 [P]** `tests/runtime/test_hook_lifecycle.py` — mandatory hooks fail-loud, optional hooks silent-exit.
- **T030 [P]** _(removed: workflow executor — YAML workflows have been removed from the extension.)_

### Phase 5 — CI integration

- **T031** Confirm existing conditional gates in [.github/workflows/ci.yml](../.github/workflows/ci.yml) (`Pytest (structural + scripts)`, `Pester (Windows)`, `Pytest (runtime)`) activate now that `tests/` exists; add `--junitxml` and `actions/upload-artifact` if not already present.
- **T032** Manual mutation-matrix sanity: introduce each defect in §Verification item 6; confirm exactly the expected test fails. 5/5 with no collateral.
- **T033** Add `.github/workflows/nightly.yml` — schedule daily on `main`; install .NET 10 preview via temporary `global.json`; run `tests/scripts` + `tests/runtime` against `tests/fixtures/fake-solution-net10/`. Non-blocking for one week, then promote to required.
- **T034** Update [.github/workflows/release.yml](../.github/workflows/release.yml) so `package-extensions` runs only after the full suite (structural + scripts + runtime + Pester) passes on tag.
- **T035** Verify [.github/dependabot.yml](../.github/dependabot.yml) covers `pip` (for `tests/requirements.txt`) and `github-actions`; add ecosystems if missing.

### Dependency summary

T001 → T002–T007 → T008–T023 → T024+T025 → T026–T030 → T031–T035.
