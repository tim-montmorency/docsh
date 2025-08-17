#!/bin/bash

# Fail on error, undefined vars, and fail pipelines; make globs return empty when no match
set -euo pipefail
shopt -s nullglob

## <!-- start-replace-subnav -->
## <!-- end-replace-subnav -->

# Excluded directory basenames
EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh" "tools")

# Default to the parent directory of this script (usually the repo root).
# You can still override by passing a root as the first argument.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="${1:-$DEFAULT_ROOT}"

echo "Generating subnavs for root: $ROOT_DIR"

# Extracts title from the first line starting with '# ' in README.md
get_title_from_readme() {
    local readme_path="$1"
    # Safely extract the first Markdown header (levels 1-6). If none, return empty.
    local line
    line=$(grep -m 1 -E '^#{1,6}[[:space:]]+' "$readme_path" || true)
    if [[ -n "$line" ]]; then
        echo "$line" | sed -E 's/^#{1,6}[[:space:]]+//'
    else
        printf ""
    fi
}

# Recursively generates a list of subdirectories that contain README.md, formatted as markdown links
generate_subnav_content() {
    local parent_dir="$1"
    local indent_level="$2"
    local content_lines=()

    parent_dir="${parent_dir%/}"

    for subdir in "$parent_dir"/*/; do
        if [[ -d "$subdir" ]]; then
            subdir="${subdir%/}"
            local base_dir
            base_dir=$(basename "$subdir")

            # Skip excluded basenames
            is_excluded=0
            for ex in "${EXCLUDED_DIRS[@]}"; do
                if [[ "$ex" == "$base_dir" ]]; then
                    is_excluded=1
                    break
                fi
            done
            if [[ $is_excluded -eq 1 ]]; then
                continue
            fi

            local subdir_readme="$subdir/README.md"
            if [[ -f "$subdir_readme" ]]; then
                local subdir_title
                subdir_title=$(get_title_from_readme "$subdir_readme")
                [[ -z "$subdir_title" ]] && subdir_title="$base_dir"

                local relative_path="${subdir#$ROOT_DIR/}"
                relative_path="${relative_path#/}"
                relative_path="${relative_path%/}"

                local link
                if [[ -n "$relative_path" ]]; then
                    link="/${relative_path}/"
                else
                    link="/"
                fi

                local indent=""
                for ((i=0; i<indent_level; i++)); do
                    indent+="    "  # 4 spaces
                done
                
                # Check for cover image (_cover.png or _cover.jpg)
                local cover_image=""
                if [[ -f "$subdir/_cover.png" ]]; then
                    cover_image="${base_dir}/_cover.png"
                elif [[ -f "$subdir/_cover.jpg" ]]; then
                    cover_image="${base_dir}/_cover.jpg"
                fi
                
                # Create link with image if cover exists, otherwise text link
                if [[ -n "$cover_image" ]]; then
                    content_lines+=("${indent}* [![${subdir_title}](./${cover_image})](${link})")
                else
                    content_lines+=("${indent}* [${subdir_title}](${link})")
                fi

                local sub_content
                sub_content=$(generate_subnav_content "$subdir" $((indent_level + 1)))
                if [[ -n "$sub_content" ]]; then
                    content_lines+=("$sub_content")
                fi
            fi
        fi
    done

    if [[ ${#content_lines[@]} -gt 0 ]]; then
        printf "%s\n" "${content_lines[@]}"
    else
        printf ""
    fi
}

# Replaces content between <!-- start-replace-subnav --> and <!-- end-replace-subnav --> with new content
replace_content_between_tags() {
    local readme_path="$1"
    local subnav_content="$2"

    if grep -q "<!-- start-replace-subnav -->" "$readme_path" && grep -q "<!-- end-replace-subnav -->" "$readme_path"; then
        echo "Processing $readme_path..."

        # Find line numbers of the tags
        local start_line
        start_line=$(grep -n "<!-- start-replace-subnav -->" "$readme_path" | cut -d: -f1 | head -n 1)
        local end_line
        end_line=$(grep -n "<!-- end-replace-subnav -->" "$readme_path" | cut -d: -f1 | head -n 1)

        # If for some reason start > end, skip
        if [[ -z "$start_line" || -z "$end_line" || $start_line -gt $end_line ]]; then
            echo "Skipping $readme_path, invalid tag order."
            return
        fi

        # Construct the updated file:
        # 1. Lines before start tag
        # 2. Start tag line
        # 3. New subnav content
        # 4. End tag line
        # 5. Lines after end tag
        sed -n "1,$((start_line-1))p" "$readme_path" > "$readme_path.tmp"
        sed -n "${start_line}p" "$readme_path" >> "$readme_path.tmp"
        printf "%s\n" "$subnav_content" >> "$readme_path.tmp"
        sed -n "${end_line}p" "$readme_path" >> "$readme_path.tmp"
        sed -n "$((end_line+1)),\$p" "$readme_path" >> "$readme_path.tmp"

        mv "$readme_path.tmp" "$readme_path"

        echo "Updated $readme_path with new subnav content."
    else
        echo "Skipping $readme_path, <!-- start-replace-subnav --> or <!-- end-replace-subnav --> not found."
    fi
}

# Updates the given directory's README.md with subnavigation if README.md exists
generate_readme_in_subfolders() {
    local parent_dir="$1"
    local readme_path="$parent_dir/README.md"

    if [[ ! -f "$readme_path" ]]; then
        return
    fi

    local title
    title=$(get_title_from_readme "$readme_path")
    [[ -z "$title" ]] && title=$(basename "$parent_dir")

    local subnav_content
    subnav_content=$(generate_subnav_content "$parent_dir" 0)

    replace_content_between_tags "$readme_path" "$subnav_content"
}

# Recursively walk through directories to generate and insert subnav content
generate_subnav() {
    local dir_path="$1"
    dir_path="${dir_path%/}"

    if [[ -f "$dir_path/README.md" ]]; then
        generate_readme_in_subfolders "$dir_path"
    else
        echo "Skipped directory (no README.md): $dir_path"
    fi

    for subdir in "$dir_path"/*/; do
        if [[ -d "$subdir" ]]; then
            subdir="${subdir%/}"
            local base_dir
            base_dir=$(basename "$subdir")
            # Skip excluded basenames
            is_excluded=0
            for ex in "${EXCLUDED_DIRS[@]}"; do
                if [[ "$ex" == "$base_dir" ]]; then
                    is_excluded=1
                    break
                fi
            done
            if [[ $is_excluded -eq 0 ]]; then
                generate_subnav "$subdir"
            fi
        fi
    done
}

# Start from the current directory
generate_subnav "$ROOT_DIR"
