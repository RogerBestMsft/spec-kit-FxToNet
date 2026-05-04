#!/usr/bin/env bash
# find-recommended-package-upgrades.sh
#
# Finds the minimum NuGet package version supporting modern .NET for each input package.
# Reads JSON from stdin, outputs JSON to stdout.
# Requires: curl, jq, unzip

set -euo pipefail

# Read input from stdin
INPUT=$(cat)

# Validate input
PACKAGE_COUNT=$(echo "$INPUT" | jq '.packages | length // 0')
if [ "$PACKAGE_COUNT" -eq 0 ]; then
    echo '{"recommendations":[],"reason":"packages is required and must contain at least one item."}'
    exit 0
fi

EMPTY_IDS=$(echo "$INPUT" | jq '[.packages[] | select(.packageId == null or (.packageId | tostring | ltrimstr(" ") | rtrimstr(" ")) == "")] | length')
if [ "$EMPTY_IDS" -gt 0 ]; then
    echo '{"recommendations":[],"reason":"Each package item must include a non-empty packageId."}'
    exit 0
fi

WORKSPACE_DIR=$(echo "$INPUT" | jq -r '.workspaceDirectory // empty')
NUGET_CONFIG_PATH=$(echo "$INPUT" | jq -r '.nugetConfigPath // empty')
INCLUDE_PRERELEASE=$(echo "$INPUT" | jq -r '.includePrerelease // false')

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
        # Simple XML extraction of packageSources add elements
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

    # net5.0+ pattern
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
RECOMMENDATIONS="[]"

while IFS= read -r pkg_json; do
    PACKAGE_ID=$(echo "$pkg_json" | jq -r '.packageId')
    CURRENT_VERSION=$(echo "$pkg_json" | jq -r '.currentVersion // empty')
    PACKAGE_ID_LOWER=$(echo "$PACKAGE_ID" | tr '[:upper:]' '[:lower:]')

    MIN_VERSION=""
    MIN_SUPPORTS="[]"
    MIN_FAMILIES="[]"
    FOUND_FEED=""
    HAD_METADATA=false

    while IFS= read -r source; do
        [ -z "$source" ] && continue

        # Get service index
        INDEX_URL="$source"
        [[ "$INDEX_URL" != */index.json ]] && INDEX_URL="${INDEX_URL%/}/index.json"

        SVC_INDEX=$(curl -sS --fail "$INDEX_URL" 2>/dev/null) || continue

        REG_BASE=$(echo "$SVC_INDEX" | jq -r '.resources[] | select(."@type" | tostring | startswith("RegistrationsBaseUrl")) | ."@id"' | head -1)
        [ -z "$REG_BASE" ] && continue

        # Get registration index
        REG_URL="${REG_BASE%/}/${PACKAGE_ID_LOWER}/index.json"
        REG_INDEX=$(curl -sS --fail "$REG_URL" 2>/dev/null) || continue

        # Iterate through pages and entries to find minimum modern version
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

                LISTED=$(echo "$CATALOG" | jq '.listed // true')
                [ "$LISTED" = "false" ] && continue

                VERSION=$(echo "$CATALOG" | jq -r '.version // empty')
                [ -z "$VERSION" ] && continue

                if [ "$INCLUDE_PRERELEASE" = "false" ] && [[ "$VERSION" == *-* ]]; then
                    continue
                fi

                HAD_METADATA=true

                # Check dependency groups for modern TFMs
                MATCHING_TFMS=()
                FAMILIES=()

                while IFS= read -r tfm; do
                    [ -z "$tfm" ] && continue
                    family=$(get_framework_family "$tfm")
                    if [ -n "$family" ]; then
                        MATCHING_TFMS+=("$tfm")
                        FAMILIES+=("$family")
                    fi
                done < <(echo "$CATALOG" | jq -r '.dependencyGroups[]?.targetFramework // empty' 2>/dev/null)

                if [ ${#MATCHING_TFMS[@]} -gt 0 ]; then
                    UNIQUE_TFMS=$(printf '%s\n' "${MATCHING_TFMS[@]}" | sort -u | jq -R . | jq -s .)
                    UNIQUE_FAMILIES=$(printf '%s\n' "${FAMILIES[@]}" | sort -u | jq -R . | jq -s .)

                    if [ -z "$MIN_VERSION" ]; then
                        MIN_VERSION="$VERSION"
                        MIN_SUPPORTS="$UNIQUE_TFMS"
                        MIN_FAMILIES="$UNIQUE_FAMILIES"
                        FOUND_FEED="$source"
                    fi
                    FOUND=true
                    break
                fi
            done < <(echo "$ITEMS" | jq -c '.[]' 2>/dev/null)

            $FOUND && break
        done < <(echo "$REG_INDEX" | jq -c '.items[]' 2>/dev/null)

        $FOUND && break
    done <<< "$SOURCES"

    # Check legacy flags on current version
    HAS_LEGACY_CONTENT=false
    HAS_INSTALL_SCRIPT=false

    if [ -n "$CURRENT_VERSION" ]; then
        while IFS= read -r source; do
            [ -z "$source" ] && continue
            INDEX_URL="$source"
            [[ "$INDEX_URL" != */index.json ]] && INDEX_URL="${INDEX_URL%/}/index.json"
            SVC_INDEX=$(curl -sS --fail "$INDEX_URL" 2>/dev/null) || continue

            CONTENT_BASE=$(echo "$SVC_INDEX" | jq -r '.resources[] | select(."@type" | tostring | contains("PackageBaseAddress")) | ."@id"' | head -1)
            [ -z "$CONTENT_BASE" ] && continue

            VER_LOWER=$(echo "$CURRENT_VERSION" | tr '[:upper:]' '[:lower:]')
            NUPKG_URL="${CONTENT_BASE%/}/${PACKAGE_ID_LOWER}/${VER_LOWER}/${PACKAGE_ID_LOWER}.${VER_LOWER}.nupkg"

            TEMP_FILE=$(mktemp /tmp/nupkg_XXXXXX.nupkg)
            trap "rm -f '$TEMP_FILE'" EXIT

            if curl -sS --fail -o "$TEMP_FILE" "$NUPKG_URL" 2>/dev/null; then
                FILE_LIST=$(unzip -l "$TEMP_FILE" 2>/dev/null | awk '{print $4}' || true)
                if echo "$FILE_LIST" | grep -qi '^content/'; then
                    HAS_LEGACY_CONTENT=true
                fi
                if echo "$FILE_LIST" | grep -qi '^tools/install\.ps1$'; then
                    HAS_INSTALL_SCRIPT=true
                fi
            fi
            rm -f "$TEMP_FILE"
            break
        done <<< "$SOURCES"
    fi

    # Determine if upgrade is needed
    NEEDS_UPGRADE=false
    REASON="null"

    if [ -n "$MIN_VERSION" ]; then
        if [ -z "$CURRENT_VERSION" ]; then
            NEEDS_UPGRADE=true
            REASON='"Current version is missing or invalid; review and upgrade to at least the minimum supported version."'
        else
            # Simple version comparison using sort -V
            LOWER=$(printf '%s\n%s' "$CURRENT_VERSION" "$MIN_VERSION" | sort -V | head -1)
            if [ "$LOWER" = "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "$MIN_VERSION" ]; then
                NEEDS_UPGRADE=true
            fi
        fi
    fi

    if $NEEDS_UPGRADE || $HAS_LEGACY_CONTENT || $HAS_INSTALL_SCRIPT; then
        CV="null"
        [ -n "$CURRENT_VERSION" ] && CV="\"$CURRENT_VERSION\""
        MSV="null"
        [ -n "$MIN_VERSION" ] && MSV="\"$MIN_VERSION\""
        FEED="null"
        [ -n "$FOUND_FEED" ] && FEED="\"$FOUND_FEED\""

        REC=$(jq -n \
            --arg pid "$PACKAGE_ID" \
            --argjson cv "$CV" \
            --argjson msv "$MSV" \
            --argjson supports "$MIN_SUPPORTS" \
            --argjson families "$MIN_FAMILIES" \
            --argjson feed "$FEED" \
            --argjson hlc "$HAS_LEGACY_CONTENT" \
            --argjson his "$HAS_INSTALL_SCRIPT" \
            --argjson reason "$REASON" \
            '{
                packageId: $pid,
                currentVersion: $cv,
                minimumSupportedVersion: $msv,
                supports: $supports,
                supportFamilies: $families,
                feed: $feed,
                hasLegacyContentFolder: $hlc,
                hasInstallScript: $his,
                reason: $reason
            }')

        RECOMMENDATIONS=$(echo "$RECOMMENDATIONS" | jq --argjson rec "$REC" '. + [$rec]')
    fi
done < <(echo "$INPUT" | jq -c '.packages[]')

echo "$RECOMMENDATIONS" | jq '{recommendations: ., reason: null}'
