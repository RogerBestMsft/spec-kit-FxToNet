# Plan: Deployment & Updates for the fx-to-dotnet Spec Kit Extension Family

## TL;DR

This plan describes how the 11 `fx-to-dotnet-*` Spec Kit extensions are packaged, distributed, installed, updated, and version-coordinated. The deployment model uses the **Spec Kit community catalog** for public discovery, **GitHub Releases** for artifact hosting, and **GitHub Actions CI/CD** for automated validation and publishing. All 11 extensions share one version number and are released atomically.

---

## Distribution Channels

### 1. Spec Kit Community Catalog (primary)

Users discover and install extensions via the Spec Kit CLI:

```bash
# Search
specify extension search fx-to-dotnet

# Install the full suite
specify extension add fx-to-dotnet
specify extension add fx-to-dotnet-assess
specify extension add fx-to-dotnet-plan
specify extension add fx-to-dotnet-sdk-convert
specify extension add fx-to-dotnet-build-fix
specify extension add fx-to-dotnet-package-compat
specify extension add fx-to-dotnet-multitarget
specify extension add fx-to-dotnet-web-migrate
specify extension add fx-to-dotnet-detect-project
specify extension add fx-to-dotnet-route-inventory
specify extension add fx-to-dotnet-policies
```

**Catalog registration**: Submit entries to the Spec Kit community catalog (`extensions/catalog.community.json` in the spec-kit repo). Each of the 11 extensions gets its own catalog entry pointing to its GitHub Release archive URL.

**Catalog entry format** (per extension):
```json
{
  "id": "fx-to-dotnet-assess",
  "name": ".NET Migration Assessment",
  "version": "0.1.0",
  "description": "Gather solution info, classify projects, audit package compatibility for .NET Framework to modern .NET migration",
  "author": "{org}",
  "url": "https://github.com/{org}/fx-to-dotnet-extensions/releases/download/v0.1.0/fx-to-dotnet-assess-0.1.0.zip",
  "repository": "https://github.com/{org}/fx-to-dotnet-extensions",
  "tags": ["dotnet", "migration", "modernization", "assessment"],
  "family": "fx-to-dotnet"
}
```

The `family` field (or a `tags` grouping) enables `specify extension search` to surface the full suite when a user searches for any member.

### 2. Direct URL Install (alternative)

For users who don't use the catalog, or for pre-release testing:

```bash
specify extension add fx-to-dotnet --from https://github.com/{org}/fx-to-dotnet-extensions/releases/download/v0.1.0/fx-to-dotnet-0.1.0.zip
```

### 3. Local Dev Install (development)

For contributors or users who clone the monorepo:

```bash
git clone https://github.com/{org}/fx-to-dotnet-extensions.git
cd fx-to-dotnet-extensions

# Install all extensions in dev mode
for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan fx-to-dotnet-sdk-convert \
           fx-to-dotnet-build-fix fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
           fx-to-dotnet-web-migrate fx-to-dotnet-detect-project fx-to-dotnet-route-inventory \
           fx-to-dotnet-policies; do
  specify extension add --dev "$(pwd)/spec-kit/$ext"
done
```

Dev mode symlinks the extension directory so edits are reflected immediately without reinstalling.

---

## Packaging

### Archive Format

Each extension is packaged as a `.zip` archive containing the extension directory contents (after applying `.extensionignore` exclusions). The archive name follows `{extension-id}-{version}.zip`.

### Packaging Script

A `scripts/package-extensions.sh` (and `.ps1` variant) in the monorepo root automates packaging all 11 extensions:

```
scripts/package-extensions.sh
  For each extension directory:
    1. Read version from extension.yml
    2. Apply .extensionignore exclusions
    3. Create {ext-id}-{version}.zip in releases/ directory
  Output: releases/fx-to-dotnet-0.1.0.zip
          releases/fx-to-dotnet-assess-0.1.0.zip
          ... (11 archives total)
```

### What Gets Packaged (per extension)

| Included | Excluded |
|---|---|
| `extension.yml` | `tests/` |
| `commands/*.md` | `.github/` |
| `policies/*.md` (policies extension only) | `*.pyc` |
| `scripts/` (build-fix extension only) | `.extensionignore` itself |
| `README.md` | Dev-only files |

---

## CI/CD Pipeline

### GitHub Actions Workflows

The monorepo has two workflows:

#### Workflow 1: `ci.yml` — Validation on Every Push/PR

```yaml
name: CI — Validate Extensions
on:
  push:
    branches: [main]
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Spec Kit CLI
        run: pip install speckit

      - name: Validate all extension manifests
        run: |
          for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan \
                     fx-to-dotnet-sdk-convert fx-to-dotnet-build-fix \
                     fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
                     fx-to-dotnet-web-migrate fx-to-dotnet-detect-project \
                     fx-to-dotnet-route-inventory fx-to-dotnet-policies; do
            echo "Validating $ext..."
            specify extension validate "spec-kit/$ext"
          done

      - name: Cross-reference audit
        run: |
          # Grep all commands for speckit.fx-to-dotnet-* references
          # Verify each referenced command exists in a sibling extension.yml
          python scripts/cross-reference-audit.py

      - name: Version consistency check
        run: |
          # Verify all 11 extension.yml files declare the same version
          python scripts/version-check.py

      - name: Dev install smoke test
        run: |
          for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan \
                     fx-to-dotnet-sdk-convert fx-to-dotnet-build-fix \
                     fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
                     fx-to-dotnet-web-migrate fx-to-dotnet-detect-project \
                     fx-to-dotnet-route-inventory fx-to-dotnet-policies; do
            specify extension add --dev "$(pwd)/spec-kit/$ext"
          done
          specify extension list | grep -c "fx-to-dotnet" | xargs test 11 -eq
```

#### Workflow 2: `release.yml` — Package & Publish on Tag

```yaml
name: Release Extensions
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write  # For creating GitHub Releases

    steps:
      - uses: actions/checkout@v4

      - name: Install Spec Kit CLI
        run: pip install speckit

      - name: Validate all extensions
        run: |
          for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan \
                     fx-to-dotnet-sdk-convert fx-to-dotnet-build-fix \
                     fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
                     fx-to-dotnet-web-migrate fx-to-dotnet-detect-project \
                     fx-to-dotnet-route-inventory fx-to-dotnet-policies; do
            specify extension validate "spec-kit/$ext"
          done

      - name: Extract version from tag
        id: version
        run: echo "VERSION=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Verify tag matches extension versions
        run: |
          for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan \
                     fx-to-dotnet-sdk-convert fx-to-dotnet-build-fix \
                     fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
                     fx-to-dotnet-web-migrate fx-to-dotnet-detect-project \
                     fx-to-dotnet-route-inventory fx-to-dotnet-policies; do
            EXT_VERSION=$(grep 'version:' "spec-kit/$ext/extension.yml" | head -1 | awk '{print $2}' | tr -d '"')
            if [ "$EXT_VERSION" != "${{ steps.version.outputs.VERSION }}" ]; then
              echo "ERROR: $ext version ($EXT_VERSION) does not match tag (${{ steps.version.outputs.VERSION }})"
              exit 1
            fi
          done

      - name: Package extensions
        run: |
          mkdir -p releases
          for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan \
                     fx-to-dotnet-sdk-convert fx-to-dotnet-build-fix \
                     fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
                     fx-to-dotnet-web-migrate fx-to-dotnet-detect-project \
                     fx-to-dotnet-route-inventory fx-to-dotnet-policies; do
            cd "spec-kit/$ext"
            zip -r "../../releases/${ext}-${{ steps.version.outputs.VERSION }}.zip" . \
              -x "tests/*" ".github/*" "*.pyc" ".extensionignore"
            cd ../..
          done

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: releases/*.zip
          generate_release_notes: true

      - name: Generate catalog entries
        run: python scripts/generate-catalog.py ${{ steps.version.outputs.VERSION }} > catalog-entries.json

      - name: Upload catalog entries artifact
        uses: actions/upload-artifact@v4
        with:
          name: catalog-entries
          path: catalog-entries.json
```

---

## Versioning Strategy

### Single Coordinated Version

All 11 extensions share the same version number. When any extension changes, all are released together at the new version. This prevents compatibility drift between sibling extensions that invoke each other's commands.

**Version is declared in three places** (must stay in sync):
1. Each `extension.yml` → `extension.version` field
2. Git tag (e.g., `v0.1.0`)
3. Catalog entries → `version` field

### Versioning Scheme

SemVer (`MAJOR.MINOR.PATCH`):
- **MAJOR**: Breaking changes to command interfaces, state file format changes requiring migration, renamed/removed commands
- **MINOR**: New commands, new policy docs, new features in existing commands, new extension added to the family
- **PATCH**: Bug fixes in command instructions, policy doc corrections, build script fixes

### Pre-releases

Pre-release versions use SemVer pre-release suffix: `0.2.0-beta.1`, `1.0.0-rc.1`. Pre-release archives are uploaded to GitHub Releases but NOT submitted to the community catalog.

---

## Release Process

### Step-by-Step

1. **Branch**: Create a release branch from `main` (e.g., `release/0.2.0`)
2. **Bump versions**: Update `version:` in all 11 `extension.yml` files to the new version
3. **Update CHANGELOGs**: Update root CHANGELOG.md and per-extension READMEs if needed
4. **PR & merge**: Open PR, CI validates, merge to `main`
5. **Tag**: Create annotated tag: `git tag -a v0.2.0 -m "Release 0.2.0"`
6. **Push tag**: `git push origin v0.2.0` → triggers `release.yml` workflow
7. **Automated**:
   - CI validates all extensions
   - CI verifies tag matches all `extension.yml` versions
   - CI packages 11 zip archives
   - CI creates GitHub Release with all 11 archives + auto-generated release notes
   - CI generates catalog entry JSON for community catalog PR
8. **Catalog PR**: Take the generated `catalog-entries.json` and submit a PR to the Spec Kit community catalog repo updating all 11 entries

### Version Bump Automation

A helper script bumps all 11 `extension.yml` files at once:

```bash
# scripts/bump-version.sh 0.2.0
VERSION=$1
for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan \
           fx-to-dotnet-sdk-convert fx-to-dotnet-build-fix \
           fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
           fx-to-dotnet-web-migrate fx-to-dotnet-detect-project \
           fx-to-dotnet-route-inventory fx-to-dotnet-policies; do
  sed -i "s/version: .*/version: \"$VERSION\"/" "$ext/extension.yml"
done
echo "Bumped all extensions to $VERSION"
```

---

## Update Flow (User Perspective)

### Checking for Updates

```bash
specify extension list          # Shows installed extensions + current versions
specify extension search fx-to-dotnet  # Shows latest catalog versions
```

### Updating

```bash
# Update a single extension
specify extension update fx-to-dotnet-build-fix

# Update all fx-to-dotnet extensions
for ext in fx-to-dotnet fx-to-dotnet-assess fx-to-dotnet-plan fx-to-dotnet-sdk-convert \
           fx-to-dotnet-build-fix fx-to-dotnet-package-compat fx-to-dotnet-multitarget \
           fx-to-dotnet-web-migrate fx-to-dotnet-detect-project fx-to-dotnet-route-inventory \
           fx-to-dotnet-policies; do
  specify extension update "$ext"
done
```

### Update Safety

- **In-progress migrations are safe**: Extensions only contain markdown instructions and scripts — no runtime state. The `.fx-to-dotnet/` state directory in the user's solution is unaffected by extension updates.
- **State format versioning**: If a future release changes the state file format, the orchestrator command should detect the format version and either migrate it or warn the user.
- **Rollback**: If an update causes issues, the user can pin a specific version:
  ```bash
  specify extension add fx-to-dotnet-build-fix --from https://github.com/{org}/fx-to-dotnet-extensions/releases/download/v0.1.0/fx-to-dotnet-build-fix-0.1.0.zip
  ```

---

## MCP Server Dependencies

The extensions themselves are markdown-only, but two extensions (`fx-to-dotnet-assess` and `fx-to-dotnet-sdk-convert`) require an external MCP server. This is NOT distributed as part of the extension family — it is a separate tool the user must configure. NuGet package compatibility analysis is handled by bundled skill scripts (`nuget-package-compat`) and does not require an MCP server.

### Required MCP Servers

| MCP Server | Used by | Distribution |
|---|---|---|
| `Microsoft.GitHubCopilot.AppModernization.Mcp` | assess, sdk-convert | NuGet tool package (`dnx` runner) |

### User Setup

Users must configure `.mcp.json` in their project or workspace with the MCP server entry. The root README and relevant extension READMEs include the required `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "Microsoft.GitHubCopilot.AppModernization.Mcp": {
      "type": "stdio",
      "command": "dnx",
      "args": ["Microsoft.GitHubCopilot.AppModernization.Mcp@1.0.903-preview1", "--yes"],
      "tools": ["*"]
    }
  }
}
```

The `extension.yml` for `fx-to-dotnet-assess` and `fx-to-dotnet-sdk-convert` declare `Microsoft.GitHubCopilot.AppModernization.Mcp` as a `requires.tools` entry — Spec Kit will warn the user if the tool is not available.

---

## Monorepo CI/CD Files to Create

| File | Purpose |
|---|---|
| `.github/workflows/ci.yml` | Validate all extensions on every push/PR |
| `.github/workflows/release.yml` | Package + publish to GitHub Releases on tag |
| `scripts/package-extensions.sh` | Package all 11 extensions into zip archives |
| `scripts/package-extensions.ps1` | Windows variant of packaging script |
| `scripts/bump-version.sh` | Bump version in all 11 extension.yml files |
| `scripts/bump-version.ps1` | Windows variant of version bump script |
| `scripts/cross-reference-audit.py` | Verify all cross-extension command references resolve |
| `scripts/version-check.py` | Verify all extensions declare the same version |
| `scripts/generate-catalog.py` | Generate community catalog JSON entries from extension.yml files |
| `CHANGELOG.md` | Root changelog for the extension family |

---

## Decisions

| Decision | Rationale |
|---|---|
| **GitHub Releases for hosting** | Free, reliable, supports direct URL install; no need for custom infrastructure |
| **Community catalog for discovery** | Standard Spec Kit distribution path; users find extensions via `specify extension search` |
| **Atomic versioning** | All 11 extensions share one version; prevents cross-extension compatibility drift |
| **Tag-triggered release** | Pushing a `v*` tag triggers packaging + publishing; no manual artifact creation |
| **MCP server not bundled** | `Microsoft.GitHubCopilot.AppModernization.Mcp` is a separate NuGet tool package with its own release cadence; NuGet compat analysis uses bundled skill scripts |
| **No auto-update hook** | Users explicitly update; avoids breaking in-progress migrations |

---

## Future Enhancements

1. **Meta-extension / bundle install**: Create a `fx-to-dotnet-suite` meta-extension whose sole purpose is to declare all 11 extensions as dependencies, enabling one-command install: `specify extension add fx-to-dotnet-suite`.
2. **Private catalog support**: For enterprise users who can't access the public community catalog, document how to set `SPECKIT_CATALOG_URL` to a private catalog JSON hosting the same extension archives on an internal server.
3. **Automated catalog PR**: Extend the release workflow to automatically open a PR against the Spec Kit community catalog repo with updated entries (requires a GitHub App or PAT with cross-repo write access).
4. **Telemetry / usage analytics**: If Spec Kit adds extension telemetry, opt in to track which phases are most used and where users get stuck.
5. **State format migration**: If a future version changes state file format, add a `speckit.fx-to-dotnet.migrate-state` command that upgrades `.fx-to-dotnet/` files from the old format.
