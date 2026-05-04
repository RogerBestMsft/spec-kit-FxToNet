#!/usr/bin/env bash
set -euo pipefail

# Package all spec-kit extensions into zip archives under releases/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_KIT="$SCRIPT_DIR/.."
# Honor RELEASES_DIR env override (used by CI to pin output inside the workspace).
# Default places releases one level above the workspace root for backwards compatibility.
RELEASES="${RELEASES_DIR:-$SPEC_KIT/../releases}"

# Single combined release artifact: a zip containing the extension and the
# companion preset as top-level subfolders. Naming follows the extension id.
BUNDLE_ID="fx-to-dotnet"
EXTENSION_DIR="$SPEC_KIT/fx-to-dotnet"
PRESET_DIR="$SPEC_KIT/presets/fx-to-dotnet-sdd"

if [ ! -f "$EXTENSION_DIR/extension.yml" ]; then
  echo "ERROR: $EXTENSION_DIR/extension.yml not found" >&2
  exit 1
fi
if [ ! -f "$PRESET_DIR/preset.yml" ]; then
  echo "ERROR: $PRESET_DIR/preset.yml not found" >&2
  exit 1
fi

mkdir -p "$RELEASES"
RELEASES="$(cd "$RELEASES" && pwd)"

version=$(grep 'version:' "$EXTENSION_DIR/extension.yml" | head -1 | sed 's/.*version:[[:space:]]*//' | tr -d '"')
archive="$RELEASES/${BUNDLE_ID}-${version}.zip"

echo "Packaging combined bundle $BUNDLE_ID v$version -> $archive"
rm -f "$archive"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$EXTENSION_DIR"  "$staging/fx-to-dotnet"
cp -R "$PRESET_DIR"     "$staging/fx-to-dotnet-sdd"

(cd "$staging" && zip -r "$archive" . \
  -x "*/tests/*" "*/.github/*" "*.pyc" "*/.extensionignore")

echo ""
echo "Done. $(ls "$RELEASES"/*.zip 2>/dev/null | wc -l) archive(s) in $RELEASES/"
