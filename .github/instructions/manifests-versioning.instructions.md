---
applyTo: "fx-to-dotnet/extension.yml, fx-to-dotnet/preset.yml, README.md, fx-to-dotnet/README.md, CHANGELOG.md"
description: "Rules for the extension/preset manifests, version consistency across files, README command-table claims, and the CHANGELOG release marker."
---

# Manifests, versioning & release docs

These files are validated by `tests/structural/test_extension_yaml.py`,
`test_preset_yaml.py`, `test_version_consistency.py`, `test_readme_claims.py`, and
`test_changelog.py`, with JSON schemas in [tests/schemas/](../../tests/schemas/).

## extension.yml

- Top-level: `schema_version`, `extension`, `requires`, `provides`, `hooks`, `tags`.
- `extension`: `id`, `name`, `version` (semver), `description`, `author` required;
  `repository`, `license` optional.
- `provides.commands[]`: each needs `name` (the `speckit.fx-to-dotnet.<x>` namespace) and
  `file` (path that must exist). `scripts:` lists helper paths — include **both** the
  bash and PowerShell twins, matching what the command markdown declares.
- `hooks`: maps each lifecycle event (`after_specify`, `after_plan`, `after_tasks`,
  `before_implement`, `after_implement`) to a `command`, with `optional:` and
  `description:`. All are `optional: false` **except** `after_implement`.
- Adding a command means adding it here AND creating its markdown file AND citing it in
  both READMEs. Every `name` must be unique.

## preset.yml

- `preset` (`id`, `version`, …), `requires`, `provides.templates`.
- `requires.extensions[].version` (e.g. `>=X.Y.Z`) **must be satisfied** by
  `extension.yml`'s version. `requires.speckit_version` is a lower bound.
- `provides.templates[]` each have `path` (must exist under `fx-to-dotnet/`) and
  `overrides` (the core template it replaces).

## Version consistency (enforced)

`extension.yml`, `preset.yml`, and the version lines in `README.md` must declare the
**same** semver. Change it only via:

```pwsh
pwsh support_scripts/bump-version.ps1 -NewVersion X.Y.Z   # or bump-version.sh X.Y.Z
python support_scripts/version-check.py
```

If the version's lower bound moves, also update the preset's
`requires.extensions[].version` constraint. Do not hand-edit one file in isolation.

## README claims (enforced)

`README.md` and `fx-to-dotnet/README.md` command tables may cite only commands declared
in `extension.yml`, and must cite every core (non-hook) command. Keep the hook table and
version lines in sync with the manifest.

## CHANGELOG (enforced)

`CHANGELOG.md` must start with `# Changelog` and keep the `<!-- RELEASES -->` marker —
the `update-changelog` job in `release.yml` prepends entries below it on tag publish. Do
not remove the marker or reorder the header.
