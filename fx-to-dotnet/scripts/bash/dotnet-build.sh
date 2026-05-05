#!/usr/bin/env bash
# Build a .NET project/solution and return structured output.
# Usage: dotnet-build.sh <project-or-solution-path>

set -uo pipefail

TARGET="${1:?Usage: dotnet-build.sh <project-or-solution-path>}"

echo "::build-start::"
echo "target: ${TARGET}"

# Run build but do not let a non-zero exit short-circuit the end markers.
# This matches the PowerShell pair's behavior so callers can always parse
# the structured output regardless of build outcome.
set +e
dotnet build "${TARGET}" 2>&1
EXIT_CODE=$?
set -e

echo "::build-end::"
echo "exit-code: ${EXIT_CODE}"

exit ${EXIT_CODE}
