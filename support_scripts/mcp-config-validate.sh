#!/usr/bin/env bash
# Validate that the canonical .mcp.json snippet in mcp-setup.md is well-formed
# and contains the required MCP server entry with expected properties.

set -euo pipefail

EXTENSIONS=("fx-to-dotnet")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
REQUIRED_SERVER="Microsoft.GitHubCopilot.Modernization.Mcp"

errors=()

# --- Extract JSON block from markdown ---
extract_json_block() {
    local file="$1"
    sed -n '/^```json$/,/^```$/p' "$file" | sed '1d;$d'
}

# --- Validate JSON snippet ---
validate_mcp_config() {
    local json_text="$1"
    local source_file="$2"

    # Check valid JSON
    if ! echo "$json_text" | python3 -m json.tool > /dev/null 2>&1; then
        errors+=("${source_file}: invalid JSON in canonical snippet")
        return
    fi

    # Check top-level mcpServers key
    if ! echo "$json_text" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'mcpServers' in d" 2>/dev/null; then
        errors+=("${source_file}: missing top-level 'mcpServers' key")
        return
    fi

    # Check required server entry and properties via python
    local validation_output
    validation_output=$(python3 -c "
import sys, json

data = json.load(sys.stdin)
servers = data.get('mcpServers', {})
server_name = '${REQUIRED_SERVER}'
source = '${source_file}'
errs = []

if server_name not in servers:
    errs.append(f'{source}: missing required server \"{server_name}\" under mcpServers')
else:
    s = servers[server_name]
    if s.get('type') != 'stdio':
        errs.append(f'{source}: server type should be \"stdio\", got \"{s.get(\"type\")}\"')
    if s.get('command') != 'dnx':
        errs.append(f'{source}: server command should be \"dnx\", got \"{s.get(\"command\")}\"')
    args = s.get('args', [])
    if server_name not in args:
        errs.append(f'{source}: args missing package name \"{server_name}\"')
    if '--yes' not in args:
        errs.append(f'{source}: args missing \"--yes\" flag')
    if '--prerelease' not in args:
        errs.append(f'{source}: args missing \"--prerelease\" flag')
    tools = s.get('tools', [])
    if len(tools) == 0:
        errs.append(f'{source}: \"tools\" array is empty')

for e in errs:
    print(e)
sys.exit(1 if errs else 0)
" <<< "$json_text") || true

    if [ -n "$validation_output" ]; then
        while IFS= read -r line; do
            errors+=("$line")
        done <<< "$validation_output"
    fi
}

# --- Validate command references ---
validate_command_references() {
    local cmd_files=("commands/assess/assess.md" "commands/sdk-convert/convert.md")

    for ext in "${EXTENSIONS[@]}"; do
        for cmd_file in "${cmd_files[@]}"; do
            local full_path="${ROOT}/${ext}/${cmd_file}"
            local rel="${ext}/${cmd_file}"

            if [ ! -f "$full_path" ]; then
                errors+=("${rel}: file not found")
                continue
            fi

            # Grep the file directly. Avoid `echo "$text" | grep -q` because
            # `set -o pipefail` + `grep -q` can return 141 (SIGPIPE from echo
            # when grep closes its stdin early on first match), which the `!`
            # then flips to success — yielding bogus "does not reference"
            # errors for files larger than the pipe buffer.
            if ! grep -q 'policies/mcp-setup\.md' "$full_path"; then
                errors+=("${rel}: does not reference 'policies/mcp-setup.md'")
            fi

            if ! grep -q '\.mcp\.json' "$full_path"; then
                errors+=("${rel}: does not reference '.mcp.json'")
            fi

            if ! grep -q 'MCP Server Pre-flight' "$full_path"; then
                errors+=("${rel}: missing 'MCP Server Pre-flight' section")
            fi
        done
    done
}

# --- Main ---

# 1. Validate the canonical snippet in each extension's mcp-setup.md
for ext in "${EXTENSIONS[@]}"; do
    policy_file="${ROOT}/${ext}/policies/mcp-setup.md"
    rel="${ext}/policies/mcp-setup.md"

    if [ ! -f "$policy_file" ]; then
        errors+=("${rel}: policy file not found")
        continue
    fi

    echo "Validating canonical snippet in ${rel}"
    json_block=$(extract_json_block "$policy_file")

    if [ -z "$json_block" ]; then
        errors+=("${rel}: no JSON code block found")
        continue
    fi

    validate_mcp_config "$json_block" "$rel"
done

# 2. Validate consuming commands reference the policy
echo "Validating command pre-flight references"
validate_command_references

# --- Summary ---
if [ ${#errors[@]} -gt 0 ]; then
    echo ""
    echo "${#errors[@]} MCP config validation error(s):"
    for e in "${errors[@]}"; do
        echo "  $e"
    done
    exit 1
fi

echo "OK: MCP config is valid and all consuming commands reference the policy"
exit 0
