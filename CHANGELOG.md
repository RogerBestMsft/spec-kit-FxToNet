# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

New entries are prepended automatically by the `update-changelog` job in
`.github/workflows/release.yml` whenever a `vX.Y.Z` tag is published. The
content of each entry is sourced from the auto-generated GitHub release notes
for that tag.

<!-- RELEASES -->

## [Unreleased]

### Added

- **Cross-project transitive version alignment** — new `cross-project-version-alignment` policy detects NuGet packages whose assessed version will be overridden at runtime by transitive pulls from upstream consumer projects (addresses "highest version wins" mismatches across `<ProjectReference>` chains)
- New assessment step 7d performs cross-project transitive closure analysis after per-package compatibility checks
- New `## Transitive Alignment Conflicts` section in `package-updates.md` findings zone
- New `Get-TransitiveDependencyClosure` scripts (PowerShell + Bash) for resolving full NuGet transitive dependency trees via v3 REST API
- Migration Planner now reads alignment conflicts and uses the `Recommended Version` as `toVersion` in chunked update plans (overriding per-package minimum when a transitive conflict exists)
- Orchestrator phase 4b′ validation gate between package-compat and multitarget: verifies no residual transitive version conflicts remain before multitargeting begins
- New `layerProgress[N].versionAlignment` state field in orchestration state
