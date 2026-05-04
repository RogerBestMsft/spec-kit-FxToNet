# Tests

Automated test suite for the `fx-to-dotnet` Spec Kit extension.

## Layout

- `structural/` — L1 static validation of manifests, frontmatter, cross-references.
- `scripts/` — L2 behavior tests for `support_scripts/` and `fx-to-dotnet/scripts/` helpers.
- `runtime/` — L3 end-to-end with hand-rolled mock MCP responder.
- `schemas/` — JSON schemas for `extension.yml`, `preset.yml`, `workflow.yml`, MCP config.
- `fixtures/` — Minimal SDK-style csproj + a small layered fake-solution.

## Prerequisites

Python 3.9+ is required. Set up an isolated virtual environment before
installing test dependencies.

### Create and activate a virtual environment

PowerShell (Windows):

```pwsh
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

Bash (Linux / macOS / Git Bash):

```bash
python3 -m venv .venv
source .venv/bin/activate
```

To deactivate later, run `deactivate` in the same shell.

> Tip: if PowerShell blocks the activation script, allow it for the current
> user with
> `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`.

### Install test dependencies

```pwsh
python -m pip install --upgrade pip
python -m pip install -r tests/requirements.txt
```

For Pester (Windows-only PS-specific assertions):

```pwsh
Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
```

For the `dotnet build` script tests, install the .NET 8 SDK (any 8.x). The
nightly CI job pins .NET 10 preview via a temporary `global.json`.

## Running

```pwsh
# All cross-platform tests (default — fast)
pytest -q

# Parallel
pytest -q -n auto

# A single tier
pytest -q tests/structural
pytest -q tests/scripts
pytest -q tests/runtime

# Pester (Windows)
Invoke-Pester tests/scripts/Scripts.Tests.ps1 -Output Detailed
```

## Decisions captured in the suite

- LLM/agent reasoning is **not** executed in CI — only deterministic file-IO and
  MCP interactions are exercised by the runtime tier.
- PR jobs use `net8.0` fixtures; nightly job tests against .NET 10 preview SDK.
- Pester scope is **PS-only** assertions (parameter validation, error streams,
  `$LASTEXITCODE`); pytest is the source of truth for cross-platform script
  behavior.
- Mock MCP is a hand-rolled stdio JSON-RPC stub responder; record/replay of
  real MCP traffic is deferred until drift hurts.
