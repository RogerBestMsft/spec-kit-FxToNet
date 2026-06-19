#!/usr/bin/env bash
# get-transitive-dependency-closure.sh
#
# Resolves the full transitive NuGet dependency closure for a set of packages.
# Reads JSON from stdin, outputs JSON to stdout.
# Requires: curl, jq

set -euo pipefail

# Read input from stdin
INPUT=$(cat)

# Validate input
PACKAGE_COUNT=$(echo "$INPUT" | jq '.packages | length // 0')
if [ "$PACKAGE_COUNT" -eq 0 ]; then
    echo '{"resolved":{},"tree":[],"reason":"packages is required and must contain at least one item."}'
    exit 0
fi

TARGET_FRAMEWORK=$(echo "$INPUT" | jq -r '.targetFramework // empty')
if [ -z "$TARGET_FRAMEWORK" ]; then
    echo '{"resolved":{},"tree":[],"reason":"targetFramework is required."}'
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
        local sources
        sources=$(grep -i '<add\b' "$config_path" 2>/dev/null | sed -n 's/.*value="\([^"]*\)".*/\1/p' || true)
        if [ -n "$sources" ]; then
            echo "$sources"
            return
        fi
    fi

    echo "https://api.nuget.org/v3/index.json"
}

# Get registrations base URL from service index
get_registrations_base_url() {
    local source_url="$1"
    local index_url

    if [[ "$source_url" == */index.json ]]; then
        index_url="$source_url"
    else
        index_url="${source_url%/}/index.json"
    fi

    local index_response
    index_response=$(curl -sS --fail "$index_url" 2>/dev/null) || return 1

    echo "$index_response" | jq -r '.resources[] | select(."@type" | test("RegistrationsBaseUrl")) | ."@id"' | head -1
}

# Get framework family for TFM
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
    if [[ "$suffix" =~ ^([0-9]+)\. ]]; then
        local major="${BASH_REMATCH[1]}"
        if [ "$major" -ge 5 ]; then
            echo "netcore"
            return
        fi
    fi
}

# Score TFM compatibility (higher is better, -1 means incompatible)
score_tfm_compat() {
    local dep_tfm="$1"
    local target_tfm="$2"

    dep_tfm=$(echo "$dep_tfm" | tr '[:upper:]' '[:lower:]')
    target_tfm=$(echo "$target_tfm" | tr '[:upper:]' '[:lower:]')

    if [ "$dep_tfm" = "$target_tfm" ]; then
        echo 1000
        return
    fi

    local dep_family target_family
    dep_family=$(get_framework_family "$dep_tfm")
    target_family=$(get_framework_family "$target_tfm")

    # netstandard is compatible with netcore targets
    if [ "$dep_family" = "netstandard" ] && [ "$target_family" = "netcore" ]; then
        echo 100
        return
    fi

    # netcore dep for netcore target
    if [ "$dep_family" = "netcore" ] && [ "$target_family" = "netcore" ]; then
        echo 500
        return
    fi

    echo "-1"
}

# Parse minimum version from a NuGet version range
parse_version_range() {
    local range="$1"
    if [ -z "$range" ]; then
        echo ""
        return
    fi

    # Simple version (no brackets)
    if [[ "$range" != *"["* ]] && [[ "$range" != *"("* ]]; then
        echo "$range"
        return
    fi

    # Extract lower bound from range notation
    local cleaned
    cleaned=$(echo "$range" | sed 's/^[\[\(]//; s/[\]\)]$//')
    local lower
    lower=$(echo "$cleaned" | cut -d',' -f1 | xargs)

    if [ -n "$lower" ]; then
        echo "$lower"
    fi
}

# Compare two version strings. Returns: -1, 0, or 1
compare_versions() {
    local v1="${1%%-*}"  # strip pre-release
    local v2="${2%%-*}"

    # Pad versions to have same number of parts
    IFS='.' read -ra parts1 <<< "$v1"
    IFS='.' read -ra parts2 <<< "$v2"

    local max=${#parts1[@]}
    if [ ${#parts2[@]} -gt "$max" ]; then
        max=${#parts2[@]}
    fi

    for ((i=0; i<max; i++)); do
        local p1=${parts1[$i]:-0}
        local p2=${parts2[$i]:-0}
        if [ "$p1" -gt "$p2" ] 2>/dev/null; then
            echo "1"
            return
        elif [ "$p1" -lt "$p2" ] 2>/dev/null; then
            echo "-1"
            return
        fi
    done

    echo "0"
}

# Initialize
SOURCES=$(resolve_nuget_sources)
REGISTRATIONS_BASE_URL=""

while IFS= read -r source; do
    [ -z "$source" ] && continue
    url=$(get_registrations_base_url "$source" 2>/dev/null) || continue
    if [ -n "$url" ]; then
        REGISTRATIONS_BASE_URL="$url"
        break
    fi
done <<< "$SOURCES"

if [ -z "$REGISTRATIONS_BASE_URL" ]; then
    echo '{"resolved":{},"tree":[],"reason":"Could not connect to any NuGet source or find RegistrationsBaseUrl."}'
    exit 0
fi

# Temporary directory for caching
CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$CACHE_DIR"' EXIT

# Get dependencies for a specific package version
get_package_dependencies() {
    local pkg_id="$1"
    local version="$2"
    local id_lower
    id_lower=$(echo "$pkg_id" | tr '[:upper:]' '[:lower:]')

    local cache_file="$CACHE_DIR/${id_lower}_${version}.json"
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return
    fi

    local reg_url="${REGISTRATIONS_BASE_URL%/}/${id_lower}/${version,,}.json"
    local response
    response=$(curl -sS --fail "$reg_url" 2>/dev/null) || { echo "[]"; echo "[]" > "$cache_file"; return; }

    # Select best dependency group for target framework
    local deps
    deps=$(echo "$response" | jq --arg tf "$TARGET_FRAMEWORK" '
        (.catalogEntry // .) |
        (.dependencyGroups // []) |
        (map(select(.targetFramework != null)) |
         sort_by(
            if (.targetFramework | ascii_downcase) == ($tf | ascii_downcase) then -1000
            elif (.targetFramework | ascii_downcase | startswith("netstandard")) then -100
            elif (.targetFramework | ascii_downcase | test("^net[0-9]+\\.")) then -500
            else 0 end
         ) | .[0] // { dependencies: [] }) |
        (.dependencies // []) |
        map({ packageId: .id, versionRange: (.range // .version // "") })
    ' 2>/dev/null) || deps="[]"

    echo "$deps" > "$cache_file"
    echo "$deps"
}

# Main resolution loop using BFS
resolve_closure() {
    local resolved_file="$CACHE_DIR/resolved.json"
    local tree_file="$CACHE_DIR/tree.json"
    local queue_file="$CACHE_DIR/queue.json"
    local processed_file="$CACHE_DIR/processed.txt"

    echo "{}" > "$resolved_file"
    echo "[]" > "$tree_file"
    touch "$processed_file"

    # Initialize queue and resolved map from direct packages
    echo "$INPUT" | jq -c '.packages[] | { packageId: .packageId, version: .version }' > "$queue_file"

    # Seed resolved map
    while IFS= read -r pkg; do
        local id ver id_lower
        id=$(echo "$pkg" | jq -r '.packageId')
        ver=$(echo "$pkg" | jq -r '.version')
        id_lower=$(echo "$id" | tr '[:upper:]' '[:lower:]')
        resolved_json=$(jq --arg k "$id_lower" --arg v "$ver" '.[$k] = $v' "$resolved_file")
        echo "$resolved_json" > "$resolved_file"
    done < "$queue_file"

    # BFS
    while [ -s "$queue_file" ]; do
        local next_queue="$CACHE_DIR/next_queue.json"
        : > "$next_queue"

        while IFS= read -r item; do
            local pkg_id pkg_ver process_key
            pkg_id=$(echo "$item" | jq -r '.packageId')
            pkg_ver=$(echo "$item" | jq -r '.version')
            process_key="$(echo "$pkg_id" | tr '[:upper:]' '[:lower:]')|$pkg_ver"

            if grep -qxF "$process_key" "$processed_file" 2>/dev/null; then
                continue
            fi
            echo "$process_key" >> "$processed_file"

            # Get dependencies
            local deps
            deps=$(get_package_dependencies "$pkg_id" "$pkg_ver")

            # Add to tree
            local tree_entry
            tree_entry=$(jq -nc --arg id "$pkg_id" --arg ver "$pkg_ver" --argjson deps "$deps" \
                '{ packageId: $id, version: $ver, dependencies: $deps }')
            tree_json=$(jq --argjson entry "$tree_entry" '. += [$entry]' "$tree_file")
            echo "$tree_json" > "$tree_file"

            # Process each dependency
            echo "$deps" | jq -c '.[]' 2>/dev/null | while IFS= read -r dep; do
                local dep_id dep_range dep_min_ver dep_id_lower
                dep_id=$(echo "$dep" | jq -r '.packageId')
                dep_range=$(echo "$dep" | jq -r '.versionRange')
                dep_min_ver=$(parse_version_range "$dep_range")

                [ -z "$dep_min_ver" ] && continue

                dep_id_lower=$(echo "$dep_id" | tr '[:upper:]' '[:lower:]')
                local existing_ver
                existing_ver=$(jq -r --arg k "$dep_id_lower" '.[$k] // empty' "$resolved_file")

                if [ -n "$existing_ver" ]; then
                    local cmp
                    cmp=$(compare_versions "$dep_min_ver" "$existing_ver")
                    if [ "$cmp" = "1" ]; then
                        # Higher version — update resolved and re-queue
                        resolved_json=$(jq --arg k "$dep_id_lower" --arg v "$dep_min_ver" '.[$k] = $v' "$resolved_file")
                        echo "$resolved_json" > "$resolved_file"
                        echo "{\"packageId\":\"$dep_id\",\"version\":\"$dep_min_ver\"}" >> "$next_queue"
                    fi
                else
                    resolved_json=$(jq --arg k "$dep_id_lower" --arg v "$dep_min_ver" '.[$k] = $v' "$resolved_file")
                    echo "$resolved_json" > "$resolved_file"
                    echo "{\"packageId\":\"$dep_id\",\"version\":\"$dep_min_ver\"}" >> "$next_queue"
                fi
            done
        done < "$queue_file"

        mv "$next_queue" "$queue_file"
    done

    # Produce output
    jq -nc --slurpfile resolved "$resolved_file" --slurpfile tree "$tree_file" \
        '{ resolved: $resolved[0], tree: $tree[0], reason: null }'
}

resolve_closure
