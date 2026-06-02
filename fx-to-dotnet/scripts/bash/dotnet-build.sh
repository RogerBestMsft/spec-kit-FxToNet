#!/usr/bin/env bash
# Build a .NET project/solution and return structured output.
# Runs restore and build as separate phases so restore errors (NU*) can be
# distinguished from compile errors (CS*/BC*/FS*).
# Usage: dotnet-build.sh <project-or-solution-path> [--restore-only | --no-restore]

set -uo pipefail

TARGET="${1:?Usage: dotnet-build.sh <project-or-solution-path> [--restore-only | --no-restore]}"
MODE="${2:-}"

if [ "$MODE" = "--restore-only" ]; then
    # Restore-only mode: run dotnet restore and report restore errors
    echo "::restore-start::"
    echo "target: ${TARGET}"

    set +e
    dotnet restore "${TARGET}" 2>&1
    EXIT_CODE=$?
    set -e

    echo "::restore-end::"
    echo "exit-code: ${EXIT_CODE}"

    exit ${EXIT_CODE}
fi

if [ "$MODE" = "--no-restore" ]; then
    # Build-only mode: skip restore, only compile
    echo "::build-start::"
    echo "target: ${TARGET}"

    set +e
    dotnet build "${TARGET}" --no-restore 2>&1
    EXIT_CODE=$?
    set -e

    echo "::build-end::"
    echo "exit-code: ${EXIT_CODE}"

    exit ${EXIT_CODE}
fi

# Default: combined restore + build (original behavior)
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
