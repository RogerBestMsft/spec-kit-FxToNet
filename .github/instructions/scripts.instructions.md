---
applyTo: "fx-to-dotnet/scripts/**, support_scripts/**"
description: "Rules for shell/PowerShell/Python helper scripts: bash<->PowerShell parity, Windows PowerShell 5.1 compatibility, encoding, declaring scripts in extension.yml, and the cross-platform support_scripts tooling."
---

# Script authoring (`fx-to-dotnet/scripts/**`, `support_scripts/**`)

Two script families:
- **`fx-to-dotnet/scripts/{bash,powershell}/`** — runtime helpers a command invokes;
  declared per-command under `scripts:` in
  [extension.yml](../../fx-to-dotnet/extension.yml).
- **`support_scripts/`** — repo tooling (version bump, packaging, deploy, catalog,
  audits) in `.ps1` / `.sh` / `.py`.

## Bash ↔ PowerShell parity (enforced)

`tests/scripts/test_script_pairs_parity.py` requires every bash script to have a
PowerShell twin with **identical behavior**:

| bash (kebab-case) | PowerShell (PascalCase) |
|-------------------|-------------------------|
| `find-recommended-package-upgrades.sh` | `Find-RecommendedPackageUpgrades.ps1` |
| `get-minimal-package-set.sh` | `Get-MinimalPackageSet.ps1` |
| `dotnet-build.sh` | `dotnet-build.ps1` |

- Create both twins together; same inputs, outputs, and exit codes.
- List **both** paths under the command's `scripts:` array in `extension.yml`. The host
  picks the variant for its OS.

## Windows PowerShell 5.1 compatibility (enforced)

All `.ps1` must run under Windows PowerShell 5.1 (the default on Windows), not just
PowerShell 7+:

- **Encoding:** save as ASCII or UTF-8 **with BOM**. A BOM-less UTF-8 `.ps1` is read as
  the system ANSI code page in 5.1, so multi-byte chars (em-dash `—`, arrow `→`, smart
  quotes) corrupt string parsing. Prefer ASCII (`-`, `->`, `'`, `"`).
- **No PS7-only syntax:** avoid `??` (null-coalescing), `?:` (ternary), and
  `ConvertFrom-Json -AsHashtable`. Use `if/else` and a recursive
  PSCustomObject→hashtable converter instead.
- **Parser traps:** wrap `Test-Path` in parens before `-or`
  (`(Test-Path X) -or (Y)`); disambiguate drive letters in strings
  (`"${kind}:bar"`, not `"$kind:bar"`).

Parse-check any edited `.ps1`:

```pwsh
$err = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\path\to\script.ps1).Path, [ref]$null, [ref]$err) | Out-Null
$err | Format-List
```

## Bash portability

Target bash 3.2 (macOS default): no `declare -A` (associative arrays) — use functions
with `case` statements instead.

## support_scripts tooling

Use these rather than hand-editing; they back the CI gates:
- `version-check.py` — asserts `extension.yml`, `preset.yml`, and `README.md` agree.
- `bump-version.ps1` / `.sh` — the only sanctioned way to change the version.
- `cross-reference-audit.py` — verifies all `speckit.fx-to-dotnet.*` refs resolve.
- `mcp-config-validate.ps1` / `.sh` — validates the JSON in `policies/mcp-setup.md`.
- `package-extensions.*`, `deploy-extensions.*`, `remove-extensions.*` — release/lifecycle.
- `generate-catalog.py` / `.ps1` — community catalog entries.

Add a behavior test under `tests/scripts/` for new helpers, and add Pester coverage in
`tests/scripts/Scripts.Tests.ps1` where appropriate.
