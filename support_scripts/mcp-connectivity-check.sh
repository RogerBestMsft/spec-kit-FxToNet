#!/usr/bin/env bash
# Developer convenience wrapper — delegates to the deployed connectivity probe script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../fx-to-dotnet/scripts/bash/mcp-connectivity-check.sh" "$@"
