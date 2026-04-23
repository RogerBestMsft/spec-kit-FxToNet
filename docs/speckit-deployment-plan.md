# Plan: Deployment & Updates for the fx-to-dotnet Spec Kit Extension

## TL;DR

This plan describes how the single `fx-to-dotnet` Spec Kit extension is packaged, distributed, installed, updated, and version-coordinated. The deployment model uses the **Spec Kit community catalog** for public discovery, **GitHub Releases** for artifact hosting, and **GitHub Actions CI/CD** for automated validation and publishing.

> **Note**: This plan was originally written for 11 separate extensions. The project has since been consolidated into a single extension with 11 commands. The deployment and packaging sections below have been updated to reflect the single-extension model.

---

## Distribution Channels

### 1. Spec Kit Community Catalog (primary)

Users discover and install extensions via the Spec Kit CLI:

```bash
# Search
specify extension search fx-to-dotnet

# Install
specify extension add fx-to-dotnet
```

**Catalog registration**: Submit an entry to the Spec Kit community catalog (`extensions/catalog.community.json` in the spec-kit repo) pointing to the GitHub Release archive URL.

**Catalog entry format**:
```json
{
  "id": "fx-to-dotnet",
  "name": ".NET Framework to Modern .NET Migration",
  "version": "0.1.0",
  "description": "Orchestrate end-to-end .NET Framework to modern .NET migration across 7 phases with 11 commands",
  "author": "{org}",
  "url": "https://github.com/{org}/fx-to-dotnet-extensions/releases/download/v0.1.0/fx-to-dotnet-0.1.0.zip",
  "repository": "https://github.com/{org}/fx-to-dotnet-extensions",
  "tags": ["dotnet", "migration", "modernization", "assessment"]
}
```

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

# Install in dev mode
specify extension add --dev "$(pwd)/fx-to-dotnet"
```

Dev mode symlinks the extension directory so edits are reflected immediately without reinstalling.

---

## Packaging

### Archive Format

The extension is packaged as a `.zip` archive containing the extension directory contents (after applying `.extensionignore` exclusions). The archive name follows `fx-to-dotnet-{version}.zip`.

### Packaging Script

A `scripts/package-extensions.sh` (and `.ps1` variant) in the monorepo root automates packaging:

```
scripts/package-extensions.sh
  1. Read version from fx-to-dotnet/extension.yml
  2. Apply .extensionignore exclusions
  3. Create fx-to-dotnet-{version}.zip in releases/ directory
  Output: releases/fx-to-dotnet-0.1.0.zip
```

### What Gets Packaged

| Included | Excluded |
|---|---|
| `extension.yml` | `tests/` |
| `commands/**/*.md` | `.github/` |
| `policies/*.md` | `*.pyc` |
| `scripts/` | `.extensionignore` itself |
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

      - name: Validate extension manifest
        run: |
          echo "Validating fx-to-dotnet..."
          specify extension validate fx-to-dotnet

      - name: Cross-reference audit
        run: |
          # Verify all speckit.fx-to-dotnet.* invoke references resolve to commands in extension.yml
          python scripts/cross-reference-audit.py

      - name: Version consistency check
        run: python scripts/version-check.py

      - name: Dev install smoke test
        run: |
          specify extension add --dev "$(pwd)/fx-to-dotnet"
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

      - name: Validate extension
        run: specify extension validate fx-to-dotnet

      - name: Extract version from tag
        id: version
        run: echo "VERSION=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Verify tag matches extension version
        run: |
          EXT_VERSION=$(grep 'version:' fx-to-dotnet/extension.yml | head -1 | awk '{print $2}' | tr -d '"')
          if [ "$EXT_VERSION" != "${{ steps.version.outputs.VERSION }}" ]; then
            echo "ERROR: fx-to-dotnet version ($EXT_VERSION) does not match tag (${{ steps.version.outputs.VERSION }})"
            exit 1
          fi

      - name: Package extension
        run: |
          mkdir -p releases
          cd fx-to-dotnet
          zip -r "../releases/fx-to-dotnet-${{ steps.version.outputs.VERSION }}.zip" . \
            -x "tests/*" ".github/*" "*.pyc" ".extensionignore"
          cd ..

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

The extension uses a single version number declared in `extension.yml`. All 11 commands are released together as part of the same extension.

**Version is declared in three places** (must stay in sync):
1. Each `extension.yml` → `extension.version` field
2. Git tag (e.g., `v0.1.0`)
3. Catalog entries → `version` field

### Versioning Scheme

SemVer (`MAJOR.MINOR.PATCH`):
- **MAJOR**: Breaking changes to command interfaces, state file format changes requiring migration, renamed/removed commands
- **MINOR**: New commands, new policy docs, new features in existing commands
- **PATCH**: Bug fixes in command instructions, policy doc corrections, build script fixes

### Pre-releases

Pre-release versions use SemVer pre-release suffix: `0.2.0-beta.1`, `1.0.0-rc.1`. Pre-release archives are uploaded to GitHub Releases but NOT submitted to the community catalog.

---

## Release Process

### Step-by-Step

1. **Branch**: Create a release branch from `main` (e.g., `release/0.2.0`)
2. **Bump version**: Update `version:` in `fx-to-dotnet/extension.yml` to the new version
3. **Update CHANGELOGs**: Update root CHANGELOG.md and `fx-to-dotnet/README.md` if needed
4. **PR & merge**: Open PR, CI validates, merge to `main`
5. **Tag**: Create annotated tag: `git tag -a v0.2.0 -m "Release 0.2.0"`
6. **Push tag**: `git push origin v0.2.0` → triggers `release.yml` workflow
7. **Automated**:
   - CI validates all extensions
   - CI verifies tag matches `extension.yml` version
   - CI packages the extension as a zip archive
   - CI creates GitHub Release with the archive + auto-generated release notes
   - CI generates catalog entry JSON for community catalog PR
8. **Catalog PR**: Take the generated `catalog-entries.json` and submit a PR to the Spec Kit community catalog repo updating the entry

### Version Bump Automation

A helper script bumps `extension.yml`:

```bash
# scripts/bump-version.sh 0.2.0
VERSION=$1
sed -i "s/version: .*/version: \"$VERSION\"/" fx-to-dotnet/extension.yml
echo "Bumped fx-to-dotnet to $VERSION"
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
specify extension update fx-to-dotnet
```

### Update Safety

- **In-progress migrations are safe**: Extensions only contain markdown instructions and scripts — no runtime state. The `.fx-to-dotnet/` state directory in the user's solution is unaffected by extension updates.
- **State format versioning**: If a future release changes the state file format, the orchestrator command should detect the format version and either migrate it or warn the user.
- **Rollback**: If an update causes issues, the user can pin a specific version:
  ```bash
  specify extension add fx-to-dotnet --from https://github.com/{org}/fx-to-dotnet-extensions/releases/download/v0.1.0/fx-to-dotnet-0.1.0.zip
  ```

---

## MCP Server Dependencies

The extension is markdown-only, but two commands (`assess` and `convert`) require an external MCP server. This is NOT distributed as part of the extension — it is a separate tool the user must configure. NuGet package compatibility analysis is handled by bundled skill scripts (`nuget-package-compat`) and does not require an MCP server.

### Required MCP Servers

| MCP Server | Used by | Distribution |
|---|---|---|
| `Microsoft.GitHubCopilot.Modernization.Mcp` | assess, sdk-convert | NuGet tool package (`dnx` runner) |

### User Setup

Users must configure `.mcp.json` in their project or workspace with the MCP server entry. The root README and extension README include the required `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "Microsoft.GitHubCopilot.Modernization.Mcp": {
      "type": "stdio",
      "command": "dnx",
      "args": ["Microsoft.GitHubCopilot.Modernization.Mcp", "--yes", "--prerelease"],
      "tools": ["*"]
    }
  }
}
```

The `extension.yml` declares `Microsoft.GitHubCopilot.Modernization.Mcp` as a `requires.tools` entry — Spec Kit will warn the user if the tool is not available.

---

## Monorepo CI/CD Files to Create

| File | Purpose |
|---|---|
| `.github/workflows/ci.yml` | Validate all extensions on every push/PR |
| `.github/workflows/release.yml` | Package + publish to GitHub Releases on tag |
| `scripts/package-extensions.sh` | Package the extension into a zip archive |
| `scripts/package-extensions.ps1` | Windows variant of packaging script |
| `scripts/bump-version.sh` | Bump version in extension.yml |
| `scripts/bump-version.ps1` | Windows variant of version bump script |
| `scripts/cross-reference-audit.py` | Verify all cross-command invoke references resolve |
| `scripts/version-check.py` | Verify extension version is valid SemVer |
| `scripts/generate-catalog.py` | Generate community catalog JSON entries from extension.yml files |
| `CHANGELOG.md` | Root changelog for the extension |

---

## Decisions

| Decision | Rationale |
|---|---|
| **GitHub Releases for hosting** | Free, reliable, supports direct URL install; no need for custom infrastructure |
| **Community catalog for discovery** | Standard Spec Kit distribution path; users find extensions via `specify extension search` |
| **Single extension** | All 11 commands in one extension; simplifies install, update, and versioning |
| **Tag-triggered release** | Pushing a `v*` tag triggers packaging + publishing; no manual artifact creation |
| **MCP server not bundled** | `Microsoft.GitHubCopilot.Modernization.Mcp` is a separate NuGet tool package with its own release cadence; NuGet compat analysis uses bundled skill scripts |
| **No auto-update hook** | Users explicitly update; avoids breaking in-progress migrations |

---

## Future Enhancements

1. **Extension discovery improvements**: Enhance catalog tags and search to help users find the extension for their specific migration scenario.
2. **Private catalog support**: For enterprise users who can't access the public community catalog, document how to set `SPECKIT_CATALOG_URL` to a private catalog JSON hosting the same extension archives on an internal server.
3. **Automated catalog PR**: Extend the release workflow to automatically open a PR against the Spec Kit community catalog repo with updated entries (requires a GitHub App or PAT with cross-repo write access).
4. **Telemetry / usage analytics**: If Spec Kit adds extension telemetry, opt in to track which phases are most used and where users get stuck.
5. **State format migration**: If a future version changes state file format, add a `speckit.fx-to-dotnet.migrate-state` command that upgrades `.fx-to-dotnet/` files from the old format.







