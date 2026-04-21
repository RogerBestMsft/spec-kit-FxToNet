#!/usr/bin/env bash
set -euo pipefail

# Remove all spec-kit fx-to-dotnet extensions from the local Spec Kit installation.
# Usage: remove-extensions.sh [--force]

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

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

if [ "$FORCE" = false ]; then
  echo "The following extensions will be removed:"
  for ext in "${EXTENSIONS[@]}"; do
    echo "  - $ext"
  done
  printf "\nAre you sure you want to remove all fx-to-dotnet extensions? (y/N) "
  read -r response
  if [[ ! "$response" =~ ^[Yy](es)?$ ]]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
fi

FORCE_ARG=()
if [ "$FORCE" = true ]; then
  FORCE_ARG=(--force)
fi

for ext in "${EXTENSIONS[@]}"; do
  echo "Removing $ext..."
  if ! specify extension remove "$ext" "${FORCE_ARG[@]}" 2>/dev/null; then
    echo "  $ext was not installed, skipping"
  fi
done

echo ""
echo "Done. All fx-to-dotnet extensions removed."
