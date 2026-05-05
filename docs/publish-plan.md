# Publish Plan: fx-to-dotnet Extension and fx-to-dotnet-sdd Preset

**Status**: Draft for review
**Target**: spec-kit community catalog (public)
**Source repo**: `https://github.com/RogerBestMsft/spec-kit-FxToNet`
**Target version**: 1.0.0 (extension and preset)

## Summary

Publish the `fx-to-dotnet` extension and `fx-to-dotnet-sdd` preset to the public
spec-kit community catalogs. Policies are bundled inside the extension archive
at `fx-to-dotnet/policies/`.
Flow: prepare repo → bump versions → tag GitHub releases → submit two PRs to
`github/spec-kit` adding entries to `extensions/catalog.community.json` and
`presets/catalog.community.json`.

## Decisions

- **Layout**: monorepo (this workspace) hosts both artifacts. Per-artifact zips
  produced by zipping each artifact's directory contents so the manifest
  (`extension.yml` / `preset.yml`) sits at the archive root.
- **Versions**: extension `0.5.0 → 1.0.0`, preset `0.4.0 → 1.0.0`.
- **Policies**: bundled inside the extension archive under
  `fx-to-dotnet/policies/` (no separate staging step required).
- **Destination**: public submission to `github/spec-kit` community catalogs;
  `verified: false` initially (verification follows on maintainer review).

## Excluded scope

- Submission to the official (non-community) `catalog.json`.
- Promotion to `verified: true` (owned by spec-kit maintainers).
- Per-policy standalone publishing (no spec-kit catalog exists for policies).
- Splitting into separate ext/preset repos.

## Phase 1 — Repository preparation

1. Confirm monorepo layout. The publishing guide assumes one artifact per
   archive with the manifest at archive root. The current
   [package-extensions.ps1](../scripts/package-extensions.ps1) already produces
   a zip of `fx-to-dotnet/*`; mirror that for the preset.
2. Update `repository` URLs from `AzureAD/fx-to-dotnet-extensions` to
   `https://github.com/RogerBestMsft/spec-kit-FxToNet`:
   - [fx-to-dotnet/extension.yml](../fx-to-dotnet/extension.yml#L22)
   - [fx-to-dotnet/preset.yml](../fx-to-dotnet/preset.yml#L8)
3. Policies live under `fx-to-dotnet/policies/` and are included automatically
   when [package-extensions.ps1](../scripts/package-extensions.ps1) /
   [package-extensions.sh](../scripts/package-extensions.sh) zip the extension
   directory — no separate staging step is required.
4. Add publishing-required files at each artifact root:
   - `fx-to-dotnet/LICENSE` — copy from repo [LICENSE](../LICENSE).
   - `fx-to-dotnet/CHANGELOG.md` — v1.0.0 baseline entry.
   - `fx-to-dotnet/LICENSE` — copy.
   - `fx-to-dotnet/CHANGELOG.md` — v1.0.0 baseline entry.
   - Verify each artifact has a usable `README.md` (extension already does;
     check the preset).
5. Confirm [.extensionignore](../fx-to-dotnet/.extensionignore) exclusions
   are correct.

## Phase 2 — Version bump *(parallel with phase 1 step 5)*

1. Bump [extension.yml](../fx-to-dotnet/extension.yml#L19) `0.5.0` → `1.0.0`.
2. Bump [preset.yml](../fx-to-dotnet/preset.yml#L4) `0.4.0` → `1.0.0`.
3. Update preset's `requires.extensions[fx-to-dotnet]` constraint to `>=1.0.0`
   in [preset.yml](../fx-to-dotnet/preset.yml#L15).
4. Run [version-check.ps1](../scripts/version-check.ps1) and
   [cross-reference-audit.ps1](../scripts/cross-reference-audit.ps1) to ensure
   no stale `0.5.0` / `0.4.0` references remain.
5. Write CHANGELOG entries describing the v1.0.0 baseline.

## Phase 3 — Local validation *(depends on phases 1–2)*

1. Run [package-extensions.ps1](../scripts/package-extensions.ps1) (and the
   parallel preset packager — add one if missing) to produce zips under
   `releases/`.
2. Inspect each zip — manifest must be at the archive root (e.g. zip →
   `extension.yml`, not `fx-to-dotnet/extension.yml`).
3. Test dev install in a throwaway project:
   - `specify extension add --dev <path>/fx-to-dotnet`
   - `specify preset add --dev <path>/fx-to-dotnet`
   - Verify all 25 commands register, all 5 hooks listed, preset templates
     resolve.
4. Test archive install: `specify extension add fx-to-dotnet --from <local-zip>`.

## Phase 4 — GitHub release *(depends on phase 3)*

1. Commit + push manifest/version/CHANGELOG/policies-bundling changes to `main`.
2. Cut two tags so each artifact has its own clean download URL:
   - `ext-v1.0.0` → `archive/refs/tags/ext-v1.0.0.zip`
   - `preset-v1.0.0` → `archive/refs/tags/preset-v1.0.0.zip`
   *(Alternative: one `v1.0.0` GitHub Release with two manually attached zip
   assets and asset URLs in the catalog. Recommend two tags for simplicity.)*
3. Verify both `download_url`s are publicly reachable (anonymous fetch).
4. End-to-end install test from the public URL on a clean machine.

## Phase 5 — Catalog PRs *(depends on phase 4; PRs run in parallel)*

1. **Extension PR**: fork `github/spec-kit`, branch
   `add-fx-to-dotnet-extension`.
   - Add entry to `extensions/catalog.community.json`:
     `id: fx-to-dotnet`, `version: 1.0.0`, `verified: false`,
     `provides.commands: 25`, `provides.hooks: 5`, tags from current manifest,
     `download_url` from phase 4.
   - Add a row to the Community Extensions table in spec-kit `README.md`
     (alphabetical, category `process`, effect `Read+Write`).
   - Bump top-level `updated_at` in the catalog file.
2. **Preset PR**: branch `add-fx-to-dotnet-sdd-preset`.
   - Add entry to `presets/catalog.community.json` (alphabetical),
     `provides.templates: 3`, `provides.commands: 0`.
3. Open both PRs using the templates from each publishing guide. Cross-link
   the PRs since the preset depends on the extension.

## Relevant files

- [fx-to-dotnet/extension.yml](../fx-to-dotnet/extension.yml) — version,
  repository, 25 commands and 5 hooks.
- [fx-to-dotnet/preset.yml](../fx-to-dotnet/preset.yml)
  — version, repository, `requires.extensions` pin.
- [fx-to-dotnet/.extensionignore](../fx-to-dotnet/.extensionignore) —
  exclusion list used when zipping.
- [scripts/package-extensions.ps1](../scripts/package-extensions.ps1) /
  [.sh](../scripts/package-extensions.sh) — zip producers (need
  policies-staging update).
- [scripts/version-check.ps1](../scripts/version-check.ps1),
  [scripts/cross-reference-audit.ps1](../scripts/cross-reference-audit.ps1) —
  pre-release validators.
- [LICENSE](../LICENSE) — to be copied into both publishable artifacts.

## Verification

1. `version-check.ps1` reports `1.0.0` consistently across files.
2. `cross-reference-audit.ps1` reports zero unresolved cross-refs.
3. `unzip -l releases/fx-to-dotnet.zip` shows `extension.yml` at root
   and `policies/` directory present.
4. In a scratch repo: `specify extension add fx-to-dotnet --from <release-url>`
   succeeds; `specify extension list` shows it; running each top-level command
   produces no manifest errors.
5. `specify preset add fx-to-dotnet-sdd --from <release-url>` succeeds and
   `specify preset resolve plan-template` resolves to the preset's override.
6. Lifecycle hooks fire end-to-end: `/speckit.specify` triggers
   `speckit.fx-to-dotnet.specify-hook`, `/speckit.plan` triggers `plan-hook`,
   etc.
7. After PRs merge: `specify extension search fx-to-dotnet` and
   `specify preset search fx-to-dotnet-sdd` return the entries.

## Open questions / further considerations

1. **Tag strategy**: two per-artifact tags vs. one release with two attached
   assets. Recommend two tags. The trade-off: GitHub auto-generated archive
   URLs capture the whole repo at the tag, so each tag should be cut after
   any final per-artifact staging is committed. Manually-uploaded release
   assets give a tighter zip but add a release-time packaging step.
2. **`speckit_version` constraint**: extension currently requires `>=0.1.0`,
   preset requires `>=0.7.2`. Validate against the latest published spec-kit
   release before submitting; tighten if 1.0.0 features depend on newer APIs.
3. **`Microsoft.GitHubCopilot.Modernization.Mcp` requirement**: this MCP tool
   is declared under `requires.tools`. Confirm it's a recognized tool name in
   spec-kit's catalog conventions, or include explicit install guidance in the
   extension README so PR review isn't blocked on missing prerequisites.
