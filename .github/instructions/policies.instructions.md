---
applyTo: "fx-to-dotnet/policies/**"
description: "Authoring rules for fx-to-dotnet domain policies: POLICY.md structure, frontmatter, references/, the get_instructions loading contract, and the mcp-setup.md dual-variant JSON requirement."
---

# Policy authoring (`fx-to-dotnet/policies/**`)

Policies are the migration knowledge base. Commands load them at runtime via
`get_instructions(kind='policy', query='<policy-id>')` and must cite them in a
`## Policies Applied` table (see command-authoring rules).

## Structure

```
policies/<policy-id>/
  POLICY.md           # required; the authoritative guidance
  references/         # optional; deep-dive markdown linked from POLICY.md
```

- `<policy-id>` is **kebab-case** and is the exact `query` value commands pass to
  `get_instructions`. Keep it stable — renaming breaks every citing command.
- `mcp-setup.md` is the one policy that lives directly in `policies/` (no folder).

## POLICY.md frontmatter

```yaml
---
name: systemweb-adapters
description: "What it covers + a 'Use when: …' clause with concrete trigger types/APIs."
---
```

- `name` should match the folder/`<policy-id>`.
- Put discovery keywords in `description` using the `Use when: …` pattern (the agent
  selects policies by description).

## POLICY.md body

Typical sections: `## Policy` (the authoritative stance), `## Rules` (numbered),
`## When to Use Each Approach` (decision table), `## Migration Procedure` (steps), and a
packages/tools/references section. Link `references/*.md` with relative links
(`[migrating modules](./references/migrating-modules.md)`).

## mcp-setup.md (special — tested)

`policies/mcp-setup.md` is validated by `tests/structural/test_mcp_config.py` and
`support_scripts/mcp-config-validate.*`. It must:
- Keep **both** JSON variants valid: top-level `servers` (VS Code) and `mcpServers`
  (every other host).
- Include the `Microsoft.GitHubCopilot.Modernization.Mcp` server entry in each variant.
- Keep the Host Detection rules and Host Matrix (`{configPath}`, `{topKey}`) so commands
  can resolve the per-IDE config path without hardcoding it.

After adding or renaming a policy, update every command that cites it (the
`## Required Policies` lines and `## Policies Applied` references) and run
`python support_scripts/cross-reference-audit.py` plus `pytest tests/structural`.
