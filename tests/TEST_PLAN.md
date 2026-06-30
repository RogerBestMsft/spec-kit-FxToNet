# Test Plan — `spec-kit-FxToNet`

> **Status:** implemented. The four-tier suite plus the gap tests below make CI a
> comprehensive, deterministic pass/fail gate. **All gaps G1–G13 from both review rounds
> are closed** — their tests are folded into the coverage matrices (tagged `(Gn)`) — plus
> a one-time encoding remediation. The full suite is green: `103 passed, 9 skipped`
> (skips are shell/SDK-availability guards).

## Purpose — autonomous validation of AI-generated PRs

The goal of this plan is a single contract:

> **Green CI ⇒ the PR is mergeable without human review.**

Every invariant that an AI-authored PR could plausibly break must be caught by a
deterministic, no-LLM test that runs in CI on both Linux and Windows. Where a gap exists
today, this plan names the test that closes it. The suite intentionally executes **no
agent/LLM reasoning** — it validates file-IO, manifest/schema correctness, script
behavior, and the command↔MCP contract only.

## Suite layout

```
tests/
  conftest.py            # session fixtures: repo_root, extension_dir, preset_dir,
                         #   fixtures_dir, extension_yml, preset_yml, tmp_solution_fixture
  requirements.txt       # pytest>=8, pyyaml>=6, jsonschema>=4, pytest-xdist>=3.5
  structural/            # L1 — static manifest / markdown validation
  scripts/               # L2 — script behavior + bash<->PowerShell/Python parity
  runtime/               # L3 — deterministic end-to-end via mock MCP (no LLM)
  schemas/               # JSON Schema (draft-07) backing the structural validators
  fixtures/              # HelloLib (net10.0) + fake-solution (3-project layered)
```

### Prerequisites

- Python 3.11 + `pip install -r tests/requirements.txt`.
- A working `bash` and `pwsh` (PowerShell 7) for the scripts/runtime parity tests;
  tests that need a shell **skip** cleanly when it is absent (and skip the Windows WSL
  `bash` stub).
- .NET SDK 10.0.x for the `dotnet-build` script tests (skipped when absent).
- Pester ≥ 5 on Windows for the PowerShell-only assertions.

## Current coverage — invariant → test matrix

### L1 — Structural (`tests/structural/`)

| Test file | Invariant guarded |
|---|---|
| `test_extension_yaml.py` | `extension.yml` validates against schema; version is semver; every declared command `file` exists; every command `scripts:` entry exists on disk; every hook `command` is declared; command names unique |
| `test_preset_yaml.py` | `preset.yml` validates against schema; version is semver; `requires.extensions[].version` lower bound is satisfied by the extension version (rejects upper-bound ops); template `file`s exist |
| `test_command_frontmatter.py` | every `commands/**/*.md` has parseable frontmatter with non-empty `description`; `tools` is a list when present; `commands`/`handoffs` refs resolve to declared commands; **(G5)** when frontmatter declares `scripts`, the set equals the command's `extension.yml` `scripts:` |
| `test_cross_references.py` | `cross-reference-audit.py` exits 0; every `speckit.fx-to-dotnet.*` mention in `commands/**` resolves to a declared command |
| `test_policy_links.py` | every `policies/…/*.md` path referenced from a command body exists on disk |
| `test_readme_claims.py` | `fx-to-dotnet/README.md` command table cites no undeclared commands and cites all non-hook commands; root README version lines match the manifests |
| `test_version_consistency.py` | `version-check.py` exits 0 (single version across `extension.yml`, `preset.yml`, `README.md`) |
| `test_changelog.py` | `CHANGELOG.md` starts with `# Changelog`, keeps the `<!-- RELEASES -->` marker; released headings are semver; **(G13)** the current manifest version is tracked (released `## [x.y.z]` heading or `## [Unreleased]`) |
| `test_mcp_config.py` | `policies/mcp-setup/POLICY.md` has both `servers` (VS Code) and `mcpServers` JSON variants, each valid and including `Microsoft.GitHubCopilot.Modernization.Mcp`; documents all hosts, priority, fallback, prerequisites; `mcp-config-validate.{sh,ps1}` exit 0 |
| `test_mcp_connectivity_probe.py` | extension connectivity probe scripts exist, reference `dnxFound`/`packageResolvable`/`error` + the NuGet feed, check `dnx`, and are registered in `extension.yml` |
| `test_hook_option_b_contracts.py` | hook docs encode the Option-B contracts: fail-fast plan strictness, tasks dedupe/ordering/placeholder language, implement prerequisite boundary |
| `test_script_declarations.py` (G1) | every on-disk `scripts/{bash,powershell}/*` is declared in a command `scripts:` array; every declared script exists; every extension-script path referenced in command/policy markdown is declared + on disk |
| `test_policy_proof.py` (G3) | any command that loads a policy via `get_instructions(kind='policy', …)` emits a `## Policies Applied` heading, and vice-versa; ≥1 command proves policies |
| `test_policy_query_resolution.py` (G7) | every `get_instructions(kind='policy', query='<id>')` resolves to a `policies/<id>/` folder (allowlist for externally-provided ids); every policy folder has a `POLICY.md` |
| `test_template_cross_references.py` (G8) | every `speckit.fx-to-dotnet.*` mention in `templates/**` (preset overrides + `plan-template.md`) resolves to a declared command |
| `test_mcp_tool_references.py` (G9) | every MCP server tool (`<reverse-dns>/<tool>`) in a command's `tools` resolves to a `requires.tools` entry in `extension.yml` |
| `test_dispatch_targets.py` (G10) | `implement-hook.md` documents the `^speckit\.fx-to-dotnet\.[a-z0-9-]+$` validation regex; every documented `dispatch:` target matches the regex and resolves to a declared command |

### L2 — Scripts (`tests/scripts/`)

| Test file | Invariant guarded |
|---|---|
| `test_bump_version.py` | `bump-version.{sh,ps1}` mutate a cloned `extension.yml` on valid semver; reject non-semver |
| `test_script_pairs_parity.py` | `support_scripts/` parity: `version-check`, `cross-reference-audit`, `generate-catalog` agree across `.ps1`/`.py`; `bump-version.sh` vs `.ps1` byte-identical YAML |
| `test_generate_catalog.py` | `generate-catalog.{py,ps1}` exit 0 and emit JSON with `extensions`/`presets` and required per-entry fields |
| `test_package_extensions.py` | `package-extensions.{sh,ps1}` produce exactly one `fx-to-dotnet.zip` with `extension.yml`, `preset.yml`, ≥1 command `.md`, no stray top-level dirs |
| `test_dotnet_build_scripts.py` | `dotnet-build.{sh,ps1}` emit `::build-start::`/`::build-end::`/`exit-code:` markers, build the HelloLib fixture, and propagate non-zero exit on a bad csproj |
| `Scripts.Tests.ps1` (Pester) | PowerShell-only: parameter validation + exit codes for `bump-version`, `version-check`, `cross-reference-audit`, `generate-catalog`, `dotnet-build` |
| `test_powershell_compat.py` (G2) | every `.ps1` (extension + support) is PS 5.1-safe: no `??`/`??=`, no ternary `? :`, no `ConvertFrom-Json -AsHashtable`; non-ASCII files must be UTF-8-with-BOM |
| `test_extension_script_pairs.py` (G4) | every `fx-to-dotnet/scripts/bash/*.sh` has a PowerShell twin and vice-versa (canonical-name match); declared twins are declared together |
| `test_support_script_pairs.py` (G11) | every `support_scripts/*.sh` has a `.ps1` twin and every `.ps1` has a `.sh`/`.py` twin; `mcp-config-validate.{sh,ps1}` behavioral parity (exit 0 + `OK`) — deploy/remove/connectivity intentionally not executed (external CLI/network/mutating) |
| `test_bash_compat.py` (G12) | every `.sh` (extension + support) parses under `bash -n` and sets `-o pipefail` (exec-delegators exempt) |

### L3 — Runtime (`tests/runtime/`)

Deterministic end-to-end driven by an in-process **mock MCP**
(`Microsoft.GitHubCopilot.Modernization.Mcp` / `Swick.Mcp.Fx2dotnet`) plus a thin
command driver (`_driver.py`) that parses command markdown and performs file-IO. **No
agent reasoning is executed.**

| Test file | Invariant guarded |
|---|---|
| `test_mock_mcp.py` | mock MCP sanity: default handlers respond, calls recorded, overrides work, unknown tool raises |
| `test_assess_command_smoke.py` | `assess.md` declares the modernization MCP tool; driving it writes `analysis.md` + `package-updates.md` with required sections and issues topo-order + upgrade calls |
| `test_hook_lifecycle.py` | all 5 hooks declared and mapped; mandatory/optional flags correct; each hook file documents silent-exit on non-Framework; `implement-hook` documents fail-loud + deferral |
| `test_orchestrator_phase_order.py` | `orchestrate.md` phases present and strictly increasing in canonical order; writes `lastCompletedPhase` markers |
| `test_migration_task_order_contract.py` | `tasks-hook` ordering + dependency-safe MIG emission; `implement-hook` parse/defer-before-review; preset `implement.md` Branch A<B<C hard stop + Migration Complete checkpoint |
| `test_resume_semantics.py` | seeded `lastCompletedPhase` skips completed phases; fresh runs all; fully completed leaves none |
| `test_command_smoke_coverage.py` (G6) | contract smoke for `convert`, `fix`, `update-packages`, `web-migrate`, `multitarget-migrate`, `detect`, `inventory`, `mcp-preflight`: resolvable, non-empty description + tools list, substantive body, resolvable refs, on-disk scripts; convert↔SDK MCP tool + mock; fix↔dotnet-build wiring |

### Schemas (`tests/schemas/`)

`extension.schema.json`, `preset.schema.json`, `mcp-config.schema.json`,
`mcp-config-vscode.schema.json` — draft-07 contracts consumed by the structural
validators above.

## Recently closed gaps (G1–G6)

The six gaps from the prior review are closed; their tests now appear in the coverage
matrices above (structural / scripts / runtime), tagged `(Gn)`. Two one-time
remediations accompanied them, and three decisions shaped the contracts:

- **Decisions:** R1 policy-proof = markers-only · R2 `get-transitive-dependency-closure`
  declared under `assess` · R3 UTF-8-BOM required only for `.ps1` containing non-ASCII.
- **Manifest fix (G1):** `get-transitive-dependency-closure.{sh,ps1}` declared under the
  `assess` command in `extension.yml`.
- **Encoding remediation (G2):** added a UTF-8 BOM to 5 non-ASCII scripts
  (`Get-TransitiveDependencyClosure.ps1`, `Mcp-ConnectivityCheck.ps1`,
  `mcp-config-validate.ps1`, `mcp-connectivity-check.ps1`, `package-extensions.ps1`).
- **CI wiring:** all new tests live under the existing `tests/structural`,
  `tests/scripts`, and `tests/runtime` directories, so they are auto-collected — no
  workflow change was needed. Full suite locally: `92 passed, 7 skipped`.

## Recently closed gaps (G1–G13)

All thirteen gaps from the two review rounds are closed; their tests appear in the
coverage matrices above, tagged `(Gn)`. Highlights and the decisions that shaped them:

- **Round 1 (G1–G6):** script-declaration completeness, PS 5.1 lint, policy-proof,
  extension-script twin parity, frontmatter↔manifest script consistency, and runtime
  smoke for 8 commands. Decisions: R1 policy-proof = markers-only · R2
  `get-transitive-dependency-closure` declared under `assess` · R3 UTF-8-BOM required
  only for non-ASCII `.ps1`.
- **Round 2 (G7–G13):** policy-query→folder resolution, preset-template cross-references,
  MCP-tool↔`requires.tools` wiring, dispatch-trailer regex + target resolution,
  remaining support-script parity, bash `-n`/`pipefail` lint, and changelog
  current-version coupling.
- **Manifest fix (G1):** `get-transitive-dependency-closure.{sh,ps1}` declared under
  `assess` in `extension.yml`.
- **Encoding remediation (G2):** UTF-8 BOM added to 5 non-ASCII scripts
  (`Get-TransitiveDependencyClosure.ps1`, `Mcp-ConnectivityCheck.ps1`,
  `mcp-config-validate.ps1`, `mcp-connectivity-check.ps1`, `package-extensions.ps1`).
- **CI wiring:** all new tests live under existing `tests/structural`, `tests/scripts`,
  and `tests/runtime` directories, so they are auto-collected — no workflow change.

## Follow-ups / known caveats

Not gaps in coverage, but items a reviewer should be aware of:

- **G7 allowlist — `scenario-initialization`.** `assess.md` loads
  `get_instructions(kind='policy', query='scenario-initialization')`, which has **no
  local `policies/` folder**. It is allowlisted in `test_policy_query_resolution.py` as
  externally (MCP/core) provided. **Confirm** it is genuinely core-provided; if it is a
  typo, fix the query and remove it from the allowlist.
- **G11 behavioral scope.** `deploy-extensions`, `remove-extensions`, and the
  `support_scripts/` `mcp-connectivity-check` are guarded for twin-existence only; they
  are not executed in tests because they shell out to the external `specify` CLI / probe
  the network / mutate the host. Behavioral parity for them remains intentionally out of
  scope.
## Running the suite locally (mirrors CI)

```pwsh
python -m pip install -r tests/requirements.txt
python support_scripts/version-check.py
python support_scripts/cross-reference-audit.py
pwsh support_scripts/mcp-config-validate.ps1        # or: bash support_scripts/mcp-config-validate.sh
pytest tests/structural tests/scripts -n auto --maxfail=1
pytest tests/runtime -n auto                        # if you touched commands/hooks/orchestrator
# Windows only:
Invoke-Pester tests/scripts/Scripts.Tests.ps1
```

## CI gates / required checks

From [.github/workflows/ci.yml](../.github/workflows/ci.yml), matrix
`ubuntu-latest` + `windows-latest`, Python 3.11, .NET 10.0.x:

1. `python -m pip install -r tests/requirements.txt`
2. `python support_scripts/version-check.py`
3. `python support_scripts/cross-reference-audit.py`
4. `bash support_scripts/mcp-config-validate.sh` (Linux) / `./support_scripts/mcp-config-validate.ps1` (Windows)
5. `bash support_scripts/package-extensions.sh` smoke (Linux): exactly one `fx-to-dotnet.zip` with `extension.yml` + `preset.yml` at the root
6. `pytest tests/structural tests/scripts -n auto --maxfail=1`
7. `pytest tests/runtime -n auto`
8. `Invoke-Pester tests/scripts/Scripts.Tests.ps1` (Windows)

**Autonomy contract:** when every step above is green on both OS legs, the PR satisfies
all enforced invariants and requires no human judgement to merge. Any new invariant
added by this plan strengthens that contract without introducing non-determinism or an
LLM in the loop.

## Out of scope

- Branch-protection / required-check / auto-merge repository configuration.
- A new "validate-all" entrypoint script.
- Any build system, application code, or new runtime dependencies (tests stay on
  `pytest` + `pyyaml` + `jsonschema`).
- A maximal per-artifact coverage matrix beyond the gaps named above.
