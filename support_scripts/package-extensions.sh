#!/usr/bin/env bash
set -euo pipefail

# Package all spec-kit extensions into zip archives under releases/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_KIT="$SCRIPT_DIR/.."
# Honor RELEASES_DIR env override (used by CI to pin output inside the workspace).
# Default places releases one level above the workspace root for backwards compatibility.
RELEASES="${RELEASES_DIR:-$SPEC_KIT/../releases}"

# Three release artifacts are produced:
#   1. fx-to-dotnet-<version>.zip                  — combined bundle (extension + preset as subfolders)
#   2. fx-to-dotnet-extension-<version>.zip        — extension only (single fx-to-dotnet/ subfolder)
#   3. fx-to-dotnet-sdd-<version>.zip              — preset only (single fx-to-dotnet-sdd/ subfolder)
#
# `specify extension add`/`specify preset add` require the manifest at zip root
# or inside a single top-level subfolder, so the combined bundle is not directly
# installable; the per-artifact zips are.
BUNDLE_ID="fx-to-dotnet"
EXTENSION_ID="fx-to-dotnet"
PRESET_ID="fx-to-dotnet-sdd"
EXTENSION_DIR="$SPEC_KIT/$EXTENSION_ID"
PRESET_DIR="$SPEC_KIT/presets/$PRESET_ID"

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

bundle_archive="$RELEASES/${BUNDLE_ID}-${version}.zip"
extension_archive="$RELEASES/${EXTENSION_ID}-extension-${version}.zip"
preset_archive="$RELEASES/${PRESET_ID}-${version}.zip"

rm -f "$bundle_archive" "$extension_archive" "$preset_archive"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# Stage both artifacts as siblings; reused by all three zips.
cp -R "$EXTENSION_DIR" "$staging/$EXTENSION_ID"
cp -R "$PRESET_DIR"    "$staging/$PRESET_ID"

zip_excludes=( "*/tests/*" "*/.github/*" "*.pyc" "*/.extensionignore" )

echo "Packaging combined bundle  -> $bundle_archive"
(cd "$staging" && zip -r "$bundle_archive" "$EXTENSION_ID" "$PRESET_ID" -x "${zip_excludes[@]}")

echo "Packaging extension-only   -> $extension_archive"
(cd "$staging" && zip -r "$extension_archive" "$EXTENSION_ID" -x "${zip_excludes[@]}")

echo "Packaging preset-only      -> $preset_archive"
(cd "$staging" && zip -r "$preset_archive" "$PRESET_ID" -x "${zip_excludes[@]}")

echo ""
echo "Done. $(ls "$RELEASES"/*.zip 2>/dev/null | wc -l) archive(s) in $RELEASES/"
