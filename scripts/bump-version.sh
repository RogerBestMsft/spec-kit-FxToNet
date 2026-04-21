#!/usr/bin/env bash
set -euo pipefail

# Bump the extension version in all spec-kit extension.yml files.
# Only the extension:version field is updated; schema_version and
# requires:speckit_version are left unchanged.
# Usage: scripts/bump-version.sh 0.1.2

if [ $# -ne 1 ]; then
  echo "Usage: $0 <major.minor.patch>" >&2
  exit 1
fi

VERSION="$1"
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Version must be major.minor.patch format, got: $VERSION" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_KIT="$SCRIPT_DIR/.."

EXTENSIONS=(
  fx-to-dotnet
  fx-to-dotnet-assess
  fx-to-dotnet-plan
  fx-to-dotnet-sdk-convert
  fx-to-dotnet-build-fix
  fx-to-dotnet-package-compat
  fx-to-dotnet-multitarget
  fx-to-dotnet-web-migrate
  fx-to-dotnet-detect-project
  fx-to-dotnet-route-inventory
  fx-to-dotnet-policies
)

for ext in "${EXTENSIONS[@]}"; do
  yml="$SPEC_KIT/$ext/extension.yml"
  if [ ! -f "$yml" ]; then
    echo "WARNING: $yml not found" >&2
    continue
  fi
  # Bump extension version (indented "version:" under extension:)
  sed -i "s/^\([[:space:]]\+\)version: .*/\1version: \"$VERSION\"/" "$yml"
  echo "  $ext -> $VERSION"
done

echo "Bumped all extensions to $VERSION"
