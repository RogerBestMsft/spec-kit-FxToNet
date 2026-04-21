#!/usr/bin/env bash
# get-minimal-package-set.sh
#
# Computes the minimal subset of NuGet packages that must remain as direct PackageReference entries.
# Packages transitively provided by another package in the input set are marked for removal.
# Reads JSON from stdin, outputs JSON to stdout.
# Requires: curl, jq

set -euo pipefail

# Read input from stdin
INPUT=$(cat)

# Validate input
PACKAGE_COUNT=$(echo "$INPUT" | jq '.packages | length // 0')
if [ "$PACKAGE_COUNT" -eq 0 ]; then
    echo '{"keep":[],"removed":[],"reason":"packages is required and must contain at least one item."}'
    exit 0
fi

WORKSPACE_DIR=$(echo "$INPUT" | jq -r '.workspaceDirectory // empty')
NUGET_CONFIG_PATH=$(echo "$INPUT" | jq -r '.nugetConfigPath // empty')

# Resolve NuGet sources
resolve_nuget_sources() {
    local config_path=""

    if [ -n "$NUGET_CONFIG_PATH" ] && [ -f "$NUGET_CONFIG_PATH" ]; then
        config_path="$NUGET_CONFIG_PATH"
    elif [ -n "$WORKSPACE_DIR" ]; then
        local dir="$WORKSPACE_DIR"
        while [ "$dir" != "/" ] && [ -n "$dir" ]; do
            if [ -f "$dir/nuget.config" ] || [ -f "$dir/NuGet.config" ] || [ -f "$dir/NuGet.Config" ]; then
                config_path=$(find "$dir" -maxdepth 1 -iname 'nuget.config' -print -quit 2>/dev/null || true)
                [ -n "$config_path" ] && break
            fi
            dir=$(dirname "$dir")
        done
    fi

    if [ -n "$config_path" ]; then
        local sources
        sources=$(grep -i '<add\b' "$config_path" 2>/dev/null | sed -n 's/.*value="\([^"]*\)".*/\1/p' || true)
        if [ -n "$sources" ]; then
            echo "$sources"
            return
        fi
    fi

    echo "https://api.nuget.org/v3/index.json"
}

# Get framework family
get_framework_family() {
    local tfm
    tfm=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    if [[ "$tfm" == netstandard* ]]; then
        echo "netstandard"
        return
    fi

    if [[ "$tfm" != net* ]]; then
        return
    fi

    if [[ "$tfm" == netcoreapp* ]]; then
        echo "netcore"
        return
    fi

    local suffix="${tfm:3}"
    if [[ "$suffix" =~ ^[0-9]+\. ]]; then
        local major="${suffix%%.*}"
        if [ "$major" -ge 5 ] 2>/dev/null; then
            echo "netcore"
            return
        fi
    fi
}

SOURCES=$(resolve_nuget_sources)

# Build lookup of input package IDs (lowercase)
INPUT_IDS=$(echo "$INPUT" | jq -r '.packages[].packageId' | tr '[:upper:]' '[:lower:]' | sort -u)

# providedBy: associative array mapping lowercased depId -> list of provider IDs
declare -A PROVIDED_BY

while IFS= read -r pkg_json; do
    PACKAGE_ID=$(echo "$pkg_json" | jq -r '.packageId')
    VERSION=$(echo "$pkg_json" | jq -r '.currentVersion // empty')
    PACKAGE_ID_LOWER=$(echo "$PACKAGE_ID" | tr '[:upper:]' '[:lower:]')

    [ -z "$VERSION" ] && continue

    DEPS=""

    while IFS= read -r source; do
        [ -z "$source" ] && continue

        INDEX_URL="$source"
        [[ "$INDEX_URL" != */index.json ]] && INDEX_URL="${INDEX_URL%/}/index.json"

        SVC_INDEX=$(curl -sS --fail "$INDEX_URL" 2>/dev/null) || continue

        REG_BASE=$(echo "$SVC_INDEX" | jq -r '.resources[] | select(."@type" | tostring | startswith("RegistrationsBaseUrl")) | ."@id"' | head -1)
        [ -z "$REG_BASE" ] && continue

        REG_URL="${REG_BASE%/}/${PACKAGE_ID_LOWER}/index.json"
        REG_INDEX=$(curl -sS --fail "$REG_URL" 2>/dev/null) || continue

        FOUND=false
        while IFS= read -r page_json; do
            ITEMS=$(echo "$page_json" | jq '.items // empty')
            if [ -z "$ITEMS" ] || [ "$ITEMS" = "null" ]; then
                PAGE_URL=$(echo "$page_json" | jq -r '."@id" // empty')
                [ -z "$PAGE_URL" ] && continue
                PAGE_DATA=$(curl -sS --fail "$PAGE_URL" 2>/dev/null) || continue
                ITEMS=$(echo "$PAGE_DATA" | jq '.items // []')
            fi

            while IFS= read -r entry_json; do
                CATALOG=$(echo "$entry_json" | jq '.catalogEntry // empty')
                [ -z "$CATALOG" ] || [ "$CATALOG" = "null" ] && continue

                ENTRY_VERSION=$(echo "$CATALOG" | jq -r '.version // empty')
                if [ "$(echo "$ENTRY_VERSION" | tr '[:upper:]' '[:lower:]')" = "$(echo "$VERSION" | tr '[:upper:]' '[:lower:]')" ]; then
                    # Extract dependencies from modern framework groups
                    DEPS=$(echo "$CATALOG" | jq -r '
                        [.dependencyGroups[]? |
                         select(.targetFramework == null or .targetFramework == "" or
                                (.targetFramework | ascii_downcase |
                                 (startswith("netstandard") or startswith("netcoreapp") or
                                  (startswith("net") and (.[3:] | split(".") | .[0] | tonumber? // 0) >= 5)))) |
                         .dependencies[]?.id // empty] | unique | .[]' 2>/dev/null || true)
                    FOUND=true
                    break
                fi
            done < <(echo "$ITEMS" | jq -c '.[]' 2>/dev/null)

            $FOUND && break
        done < <(echo "$REG_INDEX" | jq -c '.items[]' 2>/dev/null)

        [ -n "$DEPS" ] && break
    done <<< "$SOURCES"

    [ -z "$DEPS" ] && continue

    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        DEP_LOWER=$(echo "$dep" | tr '[:upper:]' '[:lower:]')
        if echo "$INPUT_IDS" | grep -qx "$DEP_LOWER"; then
            if [ -z "${PROVIDED_BY[$DEP_LOWER]+x}" ]; then
                PROVIDED_BY[$DEP_LOWER]="$PACKAGE_ID"
            else
                PROVIDED_BY[$DEP_LOWER]="${PROVIDED_BY[$DEP_LOWER]}|$PACKAGE_ID"
            fi
        fi
    done <<< "$DEPS"

done < <(echo "$INPUT" | jq -c '.packages[]')

# Build results
REMOVED="[]"
KEPT="[]"

# Build set of redundant IDs
declare -A REDUNDANT_IDS
for dep_lower in "${!PROVIDED_BY[@]}"; do
    REDUNDANT_IDS[$dep_lower]=1
done

while IFS= read -r pkg_json; do
    PID=$(echo "$pkg_json" | jq -r '.packageId')
    PID_LOWER=$(echo "$PID" | tr '[:upper:]' '[:lower:]')
    CV=$(echo "$pkg_json" | jq -r '.currentVersion // empty')

    if [ -n "${REDUNDANT_IDS[$PID_LOWER]+x}" ]; then
        # This package is provided transitively
        PROVIDERS=$(echo "${PROVIDED_BY[$PID_LOWER]}" | tr '|' '\n' | sort -u | jq -R . | jq -s .)
        REC=$(jq -n \
            --arg pid "$PID" \
            --arg cv "$CV" \
            --argjson providers "$PROVIDERS" \
            '{packageId: $pid, currentVersion: $cv, providedBy: $providers}')
        REMOVED=$(echo "$REMOVED" | jq --argjson rec "$REC" '. + [$rec]')
    else
        REC=$(jq -n --arg pid "$PID" --arg cv "$CV" '{packageId: $pid, currentVersion: $cv}')
        KEPT=$(echo "$KEPT" | jq --argjson rec "$REC" '. + [$rec]')
    fi
done < <(echo "$INPUT" | jq -c '.packages[]')

REMOVED=$(echo "$REMOVED" | jq 'sort_by(.packageId)')

jq -n --argjson keep "$KEPT" --argjson removed "$REMOVED" '{keep: $keep, removed: $removed, reason: null}'
