#!/usr/bin/env bash
set -euo pipefail

# Package all spec-kit extensions into zip archives under releases/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_KIT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../.."
RELEASES="$REPO_ROOT/releases"

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

mkdir -p "$RELEASES"

for ext in "${EXTENSIONS[@]}"; do
  ext_dir="$SPEC_KIT/$ext"
  if [ ! -f "$ext_dir/extension.yml" ]; then
    echo "ERROR: $ext_dir/extension.yml not found" >&2
    exit 1
  fi

  version=$(grep 'version:' "$ext_dir/extension.yml" | head -1 | sed 's/.*version:[[:space:]]*//' | tr -d '"')
  archive="$RELEASES/${ext}-${version}.zip"

  echo "Packaging $ext v$version -> $archive"
  (cd "$ext_dir" && zip -r "$archive" . \
    -x "tests/*" ".github/*" "*.pyc" ".extensionignore")
done

echo ""
echo "Done. $(ls "$RELEASES"/*.zip 2>/dev/null | wc -l) archives in $RELEASES/"
