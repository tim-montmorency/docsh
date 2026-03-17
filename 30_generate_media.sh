#!/bin/bash
# docsh/30_generate_media.sh — Generate Markdown image lists from medias/ subfolders.
#
# For each directory under ROOT_DIR that contains both a README.md and a medias/
# folder, finds all supported image files and replaces the content between the
# start/end tags with a Markdown image list.
#
# ── Tag syntax ───────────────────────────────────────────────────────────────
#
#   <!-- start-replace-media [no-caption] -->
#   <!-- end-replace-media -->
#
# ── Attributes ───────────────────────────────────────────────────────────────
#
#   no-caption   Use a single space as alt text; images render without a caption.
#
# ── Supported extensions ─────────────────────────────────────────────────────
#
#   jpg  jpeg  png  gif  svg  webp
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash docsh/30_generate_media.sh [DIR]
#     DIR  root of the tree to scan (default: parent of the docsh/ folder)
#
#   Called automatically by docsh/autorun.sh.

# Fail on error, undefined vars, and fail pipelines; make globs return empty when no match
set -euo pipefail
shopt -s nullglob

# Directory basenames excluded from media generation
EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode")

# Supported media file extensions
SUPPORTED_EXTENSIONS=("jpg" "jpeg" "png" "gif" "svg" "webp")

# Repo root: passed as first argument, or derived from this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Format a filename as readable title-case alt text
format_alt_text() {
    local filename="$1"
    # Strip extension
    filename="${filename%.*}"
    # Underscores to spaces
    filename="${filename//_/ }"

    # Strip leading 2-digit prefix (not 4-digit years)
    if [[ "$filename" =~ ^[0-9]{2}[^0-9]\ (.*) ]]; then
        filename="${BASH_REMATCH[1]}"
    fi

    # Capitalise first letter of each word
    echo "$filename" | tr '[:upper:]' '[:lower:]' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1'
}

# Process media found in a single directory's medias/ subfolder
process_media_for_directory() {
    local dir_path="$1"
    local media_dir="$dir_path/medias"
    local readme_path="$dir_path/README.md"

    # Skip if README.md or medias/ folder is absent
    if [[ ! -f "$readme_path" || ! -d "$media_dir" ]]; then
        return
    fi

    echo "Processing media in: $dir_path"

    # Find replacement tags (with or without attributes)
    local start_tag_line
    start_tag_line=$(grep -n "<!-- start-replace-media" "$readme_path" | cut -d: -f1 | head -n 1 || true)

    if [[ -z "$start_tag_line" ]]; then
        echo "Skipping $readme_path, no media replacement tags found."
        return
    fi

    # Read the full start-tag line to parse attributes
    local start_tag_content
    start_tag_content=$(sed -n "${start_tag_line}p" "$readme_path")
    
    # Check for no-caption flag
    local no_caption=false
    if [[ "$start_tag_content" == *"no-caption"* ]]; then
        no_caption=true
        echo "no-caption mode enabled for $readme_path"
    fi

    # Require a closing end tag
    if ! grep -q "<!-- end-replace-media -->" "$readme_path"; then
        echo "Skipping $readme_path, missing end tag."
        return
    fi

    # Build the media list
    local media_content=""

    # Only process files with supported extensions in the medias/ folder
    # nullglob ensures the loop body is skipped when there are no matches
    for media_file in "$media_dir"/*.*; do
        if [[ -f "$media_file" ]]; then
            local filename
            filename=$(basename "$media_file")
            local extension="${filename##*.}"
            extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')

            # Only include supported extensions
            if [[ " ${SUPPORTED_EXTENSIONS[*]} " =~ " ${extension} " ]]; then
                if [[ "$no_caption" == true ]]; then
                    media_content+="* ![ ](./medias/${filename})"$'\n'
                else
                    local alt_text=$(format_alt_text "$filename")
                    media_content+="* ![${alt_text}](./medias/${filename})"$'\n'
                fi
            fi
        fi
    done

    # Replace content between tags
    if [[ -n "$start_tag_line" ]]; then
        local start_line end_line
        start_line=$(grep -n "<!-- start-replace-media" "$readme_path" | cut -d: -f1 | head -n 1)
        end_line=$(grep -n "<!-- end-replace-media -->" "$readme_path" | cut -d: -f1 | head -n 1)

        if [[ -z "$start_line" || -z "$end_line" || $start_line -gt $end_line ]]; then
            echo "Skipping $readme_path, invalid tag order."
            return
        fi

        sed -n "1,${start_line}p" "$readme_path" > "$readme_path.tmp"
        printf "%s\n" "$media_content" >> "$readme_path.tmp"
        sed -n "${end_line},\$p" "$readme_path" >> "$readme_path.tmp"

        mv "$readme_path.tmp" "$readme_path"
        echo "  Updated: $readme_path"
    else
        echo "Skipping $readme_path, media replacement tags not found."
    fi
}

# Recursively process all directories
process_media_recursively() {
    local dir_path="$1"
    dir_path="${dir_path%/}"

    process_media_for_directory "$dir_path"

    for subdir in "$dir_path"/*/; do
        if [[ -d "$subdir" ]]; then
            subdir="${subdir%/}"
            local base_dir
            base_dir=$(basename "$subdir")

            # Skip excluded basenames
            if [[ ! " ${EXCLUDED_DIRS[*]} " =~ " ${base_dir} " ]]; then
                process_media_recursively "$subdir"
            fi
        fi
    done
}

# Start from repo root
process_media_recursively "$ROOT_DIR"
