#!/usr/bin/env bash
# find-recommended-package-upgrades.sh
#
# Finds the minimum NuGet package version supporting modern .NET for each input package,
# with transitive constraint resolution across the input set.
# After finding per-package minimums, resolves transitive dependency constraints: if package A
# at its recommended version requires package B >= X, and B's recommendation is lower than X,
# B is bumped. Iterates until stable or max 10 iterations to prevent circular loops.
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

#region Transitive Constraint Resolution

# Build a JSON object of { packageIdLower: recommendedVersion } for all input packages
RECOMMENDED_VERSIONS="{}"
INPUT_PACKAGE_IDS="[]"

while IFS= read -r pkg_json; do
    PKG_ID=$(echo "$pkg_json" | jq -r '.packageId')
    PKG_ID_LOWER=$(echo "$PKG_ID" | tr '[:upper:]' '[:lower:]')
    CURRENT_VER=$(echo "$pkg_json" | jq -r '.currentVersion // empty')

    INPUT_PACKAGE_IDS=$(echo "$INPUT_PACKAGE_IDS" | jq --arg id "$PKG_ID_LOWER" '. + [$id]')

    # Find if there's a recommendation for this package
    REC_VER=$(echo "$RECOMMENDATIONS" | jq -r --arg pid "$PKG_ID" \
        '[.[] | select(.packageId == $pid)] | first | .minimumSupportedVersion // empty')

    if [ -n "$REC_VER" ]; then
        RECOMMENDED_VERSIONS=$(echo "$RECOMMENDED_VERSIONS" | jq --arg id "$PKG_ID_LOWER" --arg ver "$REC_VER" '. + {($id): $ver}')
    elif [ -n "$CURRENT_VER" ]; then
        RECOMMENDED_VERSIONS=$(echo "$RECOMMENDED_VERSIONS" | jq --arg id "$PKG_ID_LOWER" --arg ver "$CURRENT_VER" '. + {($id): $ver}')
    fi
done < <(echo "$INPUT" | jq -c '.packages[]')

CONSTRAINT_BUMPS="[]"
PKG_COUNT=$(echo "$RECOMMENDED_VERSIONS" | jq 'length')

if [ "$PKG_COUNT" -gt 1 ]; then
    MAX_ITERATIONS=10
    ITERATION=0

    while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do
        ITERATION=$((ITERATION + 1))
        CHANGED=false

        # For each package in our recommended set, check its transitive deps
        while IFS= read -r pkg_id; do
            [ -z "$pkg_id" ] && continue
            PKG_VERSION=$(echo "$RECOMMENDED_VERSIONS" | jq -r --arg id "$pkg_id" '.[$id] // empty')
            [ -z "$PKG_VERSION" ] && continue

            # Get registration data for this package version
            REG_BASE=""
            while IFS= read -r source; do
                [ -z "$source" ] && continue
                INDEX_URL="$source"
                [[ "$INDEX_URL" != */index.json ]] && INDEX_URL="${INDEX_URL%/}/index.json"
                SVC_INDEX=$(curl -sS --fail "$INDEX_URL" 2>/dev/null) || continue
                REG_BASE=$(echo "$SVC_INDEX" | jq -r '.resources[] | select(."@type" | tostring | startswith("RegistrationsBaseUrl")) | ."@id"' | head -1)
                [ -n "$REG_BASE" ] && break
            done <<< "$SOURCES"

            [ -z "$REG_BASE" ] && continue

            # Fetch registration entries for this package
            REG_URL="${REG_BASE%/}/${pkg_id}/index.json"
            REG_INDEX=$(curl -sS --fail "$REG_URL" 2>/dev/null) || continue

            # Find the catalog entry for the specific version and extract dependencies
            DEPS_JSON="[]"
            while IFS= read -r page_json; do
                ITEMS=$(echo "$page_json" | jq '.items // empty')
                if [ -z "$ITEMS" ] || [ "$ITEMS" = "null" ]; then
                    PAGE_URL=$(echo "$page_json" | jq -r '."@id" // empty')
                    [ -z "$PAGE_URL" ] && continue
                    PAGE_DATA=$(curl -sS --fail "$PAGE_URL" 2>/dev/null) || continue
                    ITEMS=$(echo "$PAGE_DATA" | jq '.items // []')
                fi

                # Find our specific version
                FOUND_ENTRY=$(echo "$ITEMS" | jq -c --arg ver "$PKG_VERSION" \
                    '[.[] | select(.catalogEntry.version == $ver)] | first // empty')

                if [ -n "$FOUND_ENTRY" ] && [ "$FOUND_ENTRY" != "null" ]; then
                    # Extract all dependencies across all dependency groups
                    DEPS_JSON=$(echo "$FOUND_ENTRY" | jq -c \
                        '[.catalogEntry.dependencyGroups[]?.dependencies[]? |
                          select(.id != null and .range != null) |
                          {id: (.id | ascii_downcase), range: .range}] // []')
                    break
                fi
            done < <(echo "$REG_INDEX" | jq -c '.items[]' 2>/dev/null)

            # Check each dependency against our recommended versions
            while IFS= read -r dep_json; do
                [ -z "$dep_json" ] && continue
                DEP_ID=$(echo "$dep_json" | jq -r '.id')
                DEP_RANGE=$(echo "$dep_json" | jq -r '.range')

                # Only check dependencies that are in our input set
                IN_SET=$(echo "$INPUT_PACKAGE_IDS" | jq --arg id "$DEP_ID" 'any(. == $id)')
                [ "$IN_SET" != "true" ] && continue

                # Parse version range to get lower bound
                # Handle formats: "1.0.0", "[1.0.0, )", "(, 2.0.0]", "[1.0.0]"
                REQUIRED_MIN=$(echo "$DEP_RANGE" | sed 's/^[\[\(]//; s/[\]\)]$//; s/,.*//' | tr -d ' ')
                [ -z "$REQUIRED_MIN" ] && continue

                CURRENT_REC=$(echo "$RECOMMENDED_VERSIONS" | jq -r --arg id "$DEP_ID" '.[$id] // empty')
                [ -z "$CURRENT_REC" ] && continue

                # Compare: if current recommendation is lower than required, bump it
                LOWER=$(printf '%s\n%s' "$CURRENT_REC" "$REQUIRED_MIN" | sort -V | head -1)
                if [ "$LOWER" = "$CURRENT_REC" ] && [ "$CURRENT_REC" != "$REQUIRED_MIN" ]; then
                    BUMP=$(jq -n \
                        --arg pid "$DEP_ID" \
                        --arg from "$CURRENT_REC" \
                        --arg to "$REQUIRED_MIN" \
                        --arg rb "$pkg_id" \
                        --arg rv "$REQUIRED_MIN" \
                        '{packageId: $pid, from: $from, to: $to, requiredBy: $rb, requiredVersion: $rv}')
                    CONSTRAINT_BUMPS=$(echo "$CONSTRAINT_BUMPS" | jq --argjson b "$BUMP" '. + [$b]')
                    RECOMMENDED_VERSIONS=$(echo "$RECOMMENDED_VERSIONS" | jq --arg id "$DEP_ID" --arg ver "$REQUIRED_MIN" '. + {($id): $ver}')
                    CHANGED=true
                fi
            done < <(echo "$DEPS_JSON" | jq -c '.[]' 2>/dev/null)

        done < <(echo "$RECOMMENDED_VERSIONS" | jq -r 'keys[]')

        $CHANGED || break
    done

    if [ "$ITERATION" -ge "$MAX_ITERATIONS" ] && $CHANGED; then
        echo "WARNING: Transitive constraint resolution did not converge after $MAX_ITERATIONS iterations." >&2
    fi

    # Apply bumps to recommendations
    while IFS= read -r bump_json; do
        [ -z "$bump_json" ] && continue
        BUMP_PKG_ID=$(echo "$bump_json" | jq -r '.packageId')
        BUMP_TO=$(echo "$bump_json" | jq -r '.to')
        BUMP_REQUIRED_BY=$(echo "$bump_json" | jq -r '.requiredBy')
        BUMP_REQUIRED_VER=$(echo "$bump_json" | jq -r '.requiredVersion')

        # Check if package already in recommendations
        EXISTING_IDX=$(echo "$RECOMMENDATIONS" | jq --arg pid "$BUMP_PKG_ID" \
            'to_entries | map(select(.value.packageId | ascii_downcase == ($pid | ascii_downcase))) | first | .key // -1')

        if [ "$EXISTING_IDX" != "-1" ] && [ "$EXISTING_IDX" != "null" ]; then
            # Update existing recommendation if bump target is higher
            EXISTING_MSV=$(echo "$RECOMMENDATIONS" | jq -r --argjson idx "$EXISTING_IDX" '.[$idx].minimumSupportedVersion // empty')
            if [ -z "$EXISTING_MSV" ]; then
                RECOMMENDATIONS=$(echo "$RECOMMENDATIONS" | jq --argjson idx "$EXISTING_IDX" --arg ver "$BUMP_TO" \
                    '.[$idx].minimumSupportedVersion = $ver')
            else
                HIGHER=$(printf '%s\n%s' "$EXISTING_MSV" "$BUMP_TO" | sort -V | tail -1)
                if [ "$HIGHER" = "$BUMP_TO" ] && [ "$BUMP_TO" != "$EXISTING_MSV" ]; then
                    RECOMMENDATIONS=$(echo "$RECOMMENDATIONS" | jq --argjson idx "$EXISTING_IDX" --arg ver "$BUMP_TO" \
                        '.[$idx].minimumSupportedVersion = $ver')
                fi
            fi
        else
            # Find original current version from input
            ORIG_CV=$(echo "$INPUT" | jq -r --arg pid "$BUMP_PKG_ID" \
                '[.packages[] | select(.packageId | ascii_downcase == ($pid | ascii_downcase))] | first | .currentVersion // empty')
            CV_JSON="null"
            [ -n "$ORIG_CV" ] && CV_JSON="\"$ORIG_CV\""

            REASON="Transitive constraint: $BUMP_REQUIRED_BY requires >= $BUMP_REQUIRED_VER"
            NEW_REC=$(jq -n \
                --arg pid "$BUMP_PKG_ID" \
                --argjson cv "$CV_JSON" \
                --arg msv "$BUMP_TO" \
                --arg reason "$REASON" \
                '{
                    packageId: $pid,
                    currentVersion: $cv,
                    minimumSupportedVersion: $msv,
                    supports: [],
                    supportFamilies: [],
                    feed: null,
                    hasLegacyContentFolder: false,
                    hasInstallScript: false,
                    reason: $reason
                }')
            RECOMMENDATIONS=$(echo "$RECOMMENDATIONS" | jq --argjson rec "$NEW_REC" '. + [$rec]')
        fi
    done < <(echo "$CONSTRAINT_BUMPS" | jq -c '.[]' 2>/dev/null)
fi

#endregion

echo "$RECOMMENDATIONS" | jq --argjson bumps "$CONSTRAINT_BUMPS" '{recommendations: ., constraintBumps: $bumps, reason: null}'
