# Release Pipeline Plan — GitHub Actions

> Status: **Active**. Authoritative plan for CI and release automation. See [docs/publish-plan.md](publish-plan.md) for the publication target (spec-kit community catalog) and [docs/automated-test-plan.md](automated-test-plan.md) for the eventual test suite consumed by these workflows.

## Goal

Automate the build, validation, packaging, GitHub Release, and community-catalog PR for the `fx-to-dotnet` extension and the companion `fx-to-dotnet-sdd` preset, driven by a single semantic-version tag (`v*.*.*`). Both ship together. Continuous integration runs on every PR and push to `main`.

## Tag scheme & artifacts

A single `v<MAJOR>.<MINOR>.<PATCH>` tag produces one GitHub Release with one zip asset:

- **`fx-to-dotnet-<version>.zip`** — single `fx-to-dotnet/` subfolder containing both `extension.yml` and `preset.yml`. Installable as either an extension (`specify extension add`) or a preset (`specify preset add`) since both manifests live in the same single top-level subfolder.

Dev install after unzipping: `specify extension add --dev <path>/fx-to-dotnet` and/or `specify preset add --dev <path>/fx-to-dotnet`.

The numeric portion of the tag MUST equal `extension.version` in [fx-to-dotnet/extension.yml](../fx-to-dotnet/extension.yml) AND `preset.version` in [fx-to-dotnet/preset.yml](../fx-to-dotnet/preset.yml). The release workflow fails fast if these values disagree.

## Workflows

### `.github/workflows/ci.yml` — continuous integration

| Aspect | Value |
|---|---|
| Triggers | `pull_request`, `push: main`, `workflow_call` (consumed by `release.yml`) |
| Matrix | `os: [ubuntu-latest, windows-latest]` × `python-version: ['3.11']` |
| Permissions | `contents: read` |
| Concurrency | `group: ci-${{ github.ref }}`, cancel in-progress |

Static gates (run on both OSes):
1. `support_scripts/version-check.py` — extension manifest version is parseable and consistent.
2. `support_scripts/cross-reference-audit.py` — all `speckit.fx-to-dotnet.*` references in command markdown resolve to declared commands.
3. `support_scripts/mcp-config-validate.sh` (Linux) / `mcp-config-validate.ps1` (Windows) — MCP JSON snippet in `policies/mcp-setup/POLICY.md` is well-formed.

Smoke pack (Linux only, fast):
- Run `support_scripts/package-extensions.sh` with `RELEASES_DIR=$GITHUB_WORKSPACE/releases`.
- Assert exactly one archive exists: the combined `fx-to-dotnet-<v>.zip` bundle.
- Unzip it and assert both `extension.yml` and `preset.yml` appear under `fx-to-dotnet/`.

Test gates (conditional on `tests/` existing — guarded by `if: hashFiles('tests/**') != ''`):
- `pytest tests/structural tests/scripts -n auto --maxfail=1` (both OSes).
- `pytest tests/runtime -n auto` (both OSes; mock-MCP, no network).
- `Invoke-Pester tests/scripts/Scripts.Tests.ps1` (Windows only).

The test suite is not yet implemented (see [docs/automated-test-plan.md](automated-test-plan.md)). Until it lands, only the static gates and smoke pack run; this is the intended bootstrap state.

### `.github/workflows/release.yml` — tag-driven release

| Aspect | Value |
|---|---|
| Triggers | `push: tags: ['v[0-9]+.[0-9]+.[0-9]+']`, `workflow_dispatch` (with `version` input, draft release) |
| Permissions | `contents: write` |
| Concurrency | `group: release-${{ github.ref }}`, no cancel |

Jobs:

1. **`validate`** — calls `ci.yml` via `workflow_call` to reuse all CI gates.
2. **`version-equality`** — fails if tag numeric portion `≠` extension.version `≠` preset.version. Implemented inline (small Python or `grep` snippet) so the gate is visible in the workflow file.
3. **`package`** (ubuntu-latest, needs: validate + version-equality):
   - Runs `support_scripts/package-extensions.sh` with `RELEASES_DIR=$GITHUB_WORKSPACE/releases`.
   - Computes `releases/SHA256SUMS.txt` (`sha256sum *.zip`).
   - Uploads `releases/` as a workflow artifact.
4. **`release`** (needs: package):
   - Downloads the `releases/` artifact.
   - `softprops/action-gh-release@v2`: `tag_name`, `name`, `files: releases/fx-to-dotnet.zip releases/SHA256SUMS.txt`, `generate_release_notes: true`, `draft: ${{ github.event_name == 'workflow_dispatch' }}`, `fail_on_unmatched_files: true`.
5. **`catalog-pr`** (needs: release; conditional `if: secrets.SPECKIT_CATALOG_TOKEN && !github.event.release.prerelease`):
   - Checks out `github/spec-kit` using `SPECKIT_CATALOG_TOKEN` (a fine-grained PAT or GitHub App token with `pull_requests: write` on a fork).
   - Runs `support_scripts/generate-catalog.py` from this repo and uses a small inline Python step to merge each emitted entry (matched on `id`) into `extensions/catalog.community.json` and `presets/catalog.community.json` — insert if missing, replace by `id` if present, keep `verified: false`. Both the extension entry and the preset entry point at the same combined `fx-to-dotnet-<v>.zip` (the manifests share the single `fx-to-dotnet/` subfolder, so one zip serves both install modes).
   - `peter-evans/create-pull-request@v6` opens a PR against `github/spec-kit:main` from a branch `update-fx-to-dotnet-${{ github.ref_name }}`; PR body links to the new release.
   - Skipped silently when the secret is unset (so forks and contributors don't fail builds).

### `.github/dependabot.yml`

Two ecosystems:
- `github-actions` (workflow files), weekly.
- `pip` (`tests/requirements.txt` once it exists), weekly.

## Script changes (one-time, supporting the workflows)

| Script | Change |
|---|---|
| [support_scripts/package-extensions.ps1](../support_scripts/package-extensions.ps1) | Honor `$env:RELEASES_DIR`. Build the single combined `fx-to-dotnet-<v>.zip`. |
| [support_scripts/package-extensions.sh](../support_scripts/package-extensions.sh) | Same single-zip behavior on Linux. |
| [support_scripts/generate-catalog.py](../support_scripts/generate-catalog.py) | Emit `{ "extensions": [...], "presets": [...] }`; both entries point at the combined `fx-to-dotnet-<v>.zip`. |
| [support_scripts/generate-catalog.ps1](../support_scripts/generate-catalog.ps1) | Same change for parity. |

Out of scope for this round (tracked separately):
- Test suite scaffolding (Phase 0a; see [docs/automated-test-plan.md](automated-test-plan.md)).
- Repository URL canonicalization between `extension.repository` and `preset.repository` — both currently point at `AzureAD/fx-to-dotnet-extensions`. Confirm the canonical owner before the first tagged release; `generate-catalog` derives the download URL from this field so it MUST match the repo where the GitHub Release lives.
- Marketplace publication, package signing, SBOM generation.

## Verification

1. Open a PR with a no-op change → `ci.yml` runs on Ubuntu and Windows, all static gates pass, smoke pack produces a single combined zip with both subfolders containing their respective manifests.
2. Push throwaway tag `v0.7.1-test` to a fork → `release.yml` runs end-to-end, draft release created with the combined zip + `SHA256SUMS.txt`.
3. With `SPECKIT_CATALOG_TOKEN` set on the fork → catalog PR opens against a fork of `github/spec-kit`.
4. Tag `v0.7.0` while manifests are at `0.7.1` → release fails at the version-equality job; no release is created.
5. Re-running `release.yml` via `workflow_dispatch` against the same version → `softprops/action-gh-release` refuses to overwrite because the release already exists; pipeline fails clean.

## Decisions

- **Tag scheme**: single `v*.*.*` (chosen over per-artifact tags for simplicity).
- **Artifact shape**: one combined zip with two subfolders, not two parallel zips.
- **Test gate**: full suite is the long-term gate; static gates are the bootstrap gate while the suite is being built.
- **Catalog PR**: automated, `verified: false`, manual merge upstream. Both catalog entries reference the same combined-bundle URL.
- **Cross-repo PR token**: `SPECKIT_CATALOG_TOKEN` repository secret. Catalog-PR job is skipped when the secret is absent (no failed builds for contributors).
- **Excluded**: marketplace, signing/SBOM, custom changelog beyond `generate_release_notes`.
