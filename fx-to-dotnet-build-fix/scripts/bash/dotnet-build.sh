#!/usr/bin/env bash
# Build a .NET project/solution and return structured output.
# Usage: dotnet-build.sh <project-or-solution-path>

set -euo pipefail

TARGET="${1:?Usage: dotnet-build.sh <project-or-solution-path>}"

echo "::build-start::"
echo "target: ${TARGET}"

dotnet build "${TARGET}" 2>&1
EXIT_CODE=$?

echo "::build-end::"
echo "exit-code: ${EXIT_CODE}"

exit ${EXIT_CODE}
