#!/bin/bash

# Fail on error, undefined vars, and fail pipelines; make globs return empty when no match
set -euo pipefail
shopt -s nullglob

# Calculate script and repository root paths so the sidebar is generated for the repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Directories (basenames) to exclude when walking
EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh")
# Write sidebar to the repository root
SIDEBAR_FILE="$REPO_ROOT/_sidebar.md"

# Function to extract the title from README.md
get_title_from_readme() {
    local readme_path="$1"
    local title
    title=$(grep -m 1 "^# " "$readme_path" | sed 's/^# //')
    echo "$title"
}

# Start writing to _sidebar.md (clear)
> "$SIDEBAR_FILE"

# Function to walk through directories and generate the sidebar
generate_sidebar() {
    local dir_path="$1"
    local indent="$2"

    # Check for README.md in the current directory
    if [[ -f "$dir_path/README.md" ]]; then
        local title
        title=$(get_title_from_readme "$dir_path/README.md")
        if [[ -z "$title" ]]; then
            title=$(basename "$dir_path")
        fi

        # Compute path relative to repo root and ensure it starts with a single '/'
        local rel_path
        rel_path="${dir_path#$REPO_ROOT}"
        # Remove any leading slash that remains after prefix removal
        rel_path="${rel_path#/}"
        # Trim trailing slash
        rel_path="${rel_path%/}"
        if [[ -z "$rel_path" ]]; then
            rel_path="/"
        else
            rel_path="/$rel_path/"
        fi

    # Collapse any accidental multiple slashes into a single slash (use sed)
    rel_path="$(printf '%s' "$rel_path" | sed -E 's:/{2,}:/:g')"

        echo "$indent* [$title]($rel_path)" >> "$SIDEBAR_FILE"
        echo "Added: $rel_path with title '$title'"
    else
        echo "Skipped directory (no README.md): $dir_path"
    fi

    # Recurse into subdirectories
    for subdir in "$dir_path"/*/; do
        # Ensure subdir is a directory
        if [[ -d "$subdir" ]]; then
            local base_dir
            base_dir=$(basename "$subdir")
            # Check if this directory should be excluded
            if [[ ! " ${EXCLUDED_DIRS[*]} " =~ " ${base_dir} " ]]; then
                generate_sidebar "$subdir" "  $indent"
            else
                echo "Excluding directory from recursion: $subdir"
            fi
        fi
    done
}

# Generate sidebar starting at the repository root (this includes the root README)
generate_sidebar "$REPO_ROOT" ""

echo "Sidebar generation complete: $SIDEBAR_FILE"