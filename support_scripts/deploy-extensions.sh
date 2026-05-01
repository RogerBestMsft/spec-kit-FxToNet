#!/usr/bin/env bash
set -euo pipefail

# Install all spec-kit extensions in dev mode for local development.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_KIT="$SCRIPT_DIR/.."

EXTENSIONS=(
  fx-to-dotnet
)

for ext in "${EXTENSIONS[@]}"; do
  ext_dir="$SPEC_KIT/$ext"
  if [ ! -f "$ext_dir/extension.yml" ]; then
    echo "WARNING: $ext — extension.yml not found, skipping" >&2
    continue
  fi
  echo "Installing $ext (dev mode)..."
  echo "  Console codepage: $(locale charmap 2>/dev/null || echo 'unknown')"
  specify extension add --dev "$ext_dir"
done

count=$(specify extension list | grep -c 'fx-to-dotnet' || true)
echo ""
echo "Done. $count fx-to-dotnet extension(s) installed."
