# Security Policy

`spec-kit-FxToNet` ships markdown commands/policies, YAML manifests, and paired
shell/PowerShell helper scripts that an AI agent runs during a migration. There is no
application runtime, but the scripts and CI/release workflows are part of your supply
chain — please report anything that could compromise a user's machine or repository.

## Reporting a vulnerability

**Do not open a public issue for security reports.**

Report privately via a GitHub Security Advisory:
<https://github.com/RogerBestMsft/spec-kit-FxToNet/security/advisories/new>

Please include:

- A description of the issue and its impact.
- Affected files (command, policy, script, or workflow) and version
  (see `fx-to-dotnet/extension.yml`).
- Steps to reproduce or a proof of concept.

We will acknowledge your report, investigate, and coordinate a fix and disclosure with
you. Please give us a reasonable window to remediate before any public disclosure.

## Scope examples

In scope:

- A helper script (`scripts/**`, `support_scripts/**`) that executes untrusted input,
  writes outside the intended paths, or leaks secrets.
- A CI/release workflow that could be abused to exfiltrate secrets or publish malicious
  artifacts.
- Command/policy guidance that instructs the agent to run unsafe operations.

Out of scope:

- Vulnerabilities in upstream [Spec Kit](https://github.com/github/spec-kit) — report
  those upstream.
- Issues in third-party tools the migration targets (e.g. .NET SDK, NuGet packages).
