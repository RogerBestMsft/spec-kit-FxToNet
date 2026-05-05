#!/usr/bin/env bash
set -euo pipefail

# Package the fx-to-dotnet extension (which now also ships the
# fx-to-dotnet-sdd preset alongside extension.yml) into a single zip
# archive under releases/.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_KIT="$SCRIPT_DIR/.."
# Honor RELEASES_DIR env override (used by CI to pin output inside the workspace).
# Default places releases one level above the workspace root for backwards compatibility.
RELEASES="${RELEASES_DIR:-$SPEC_KIT/../releases}"

# A single release artifact is produced:
#   fx-to-dotnet.zip — extension + companion preset together,
#                      with both extension.yml and preset.yml inside the
#                      single fx-to-dotnet/ subfolder.
#
# The archive name is unversioned; the release tag (e.g. v1.0.0) provides
# the version namespace via the GitHub Releases download URL.
#
# `specify extension add` and `specify preset add` both accept a manifest
# inside a single top-level subfolder, so this layout is installable as
# either an extension or a preset from the same zip.
BUNDLE_ID="fx-to-dotnet"
EXTENSION_ID="fx-to-dotnet"
EXTENSION_DIR="$SPEC_KIT/$EXTENSION_ID"

if [ ! -f "$EXTENSION_DIR/extension.yml" ]; then
  echo "ERROR: $EXTENSION_DIR/extension.yml not found" >&2
  exit 1
fi
if [ ! -f "$EXTENSION_DIR/preset.yml" ]; then
  echo "ERROR: $EXTENSION_DIR/preset.yml not found" >&2
  exit 1
fi

mkdir -p "$RELEASES"
RELEASES="$(cd "$RELEASES" && pwd)"

version=$(grep 'version:' "$EXTENSION_DIR/extension.yml" | head -1 | sed 's/.*version:[[:space:]]*//' | tr -d '"')
echo "Manifest version: ${version}"

bundle_archive="$RELEASES/${BUNDLE_ID}.zip"

rm -f "$bundle_archive"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# Stage the extension folder (which contains both extension.yml and preset.yml).
cp -R "$EXTENSION_DIR" "$staging/$EXTENSION_ID"

zip_excludes=( "*/tests/*" "*/.github/*" "*.pyc" "*/.extensionignore" )

echo "Packaging combined bundle  -> $bundle_archive"
(cd "$staging" && zip -r "$bundle_archive" "$EXTENSION_ID" -x "${zip_excludes[@]}")

echo ""
echo "Done. $(ls "$RELEASES"/*.zip 2>/dev/null | wc -l) archive(s) in $RELEASES/"
