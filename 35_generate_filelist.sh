#!/bin/bash
# 35_generate_filelist.sh — Generate markdown link lists from file-matching tags in README.md files.
#
# For each README.md that contains a <!-- start-replace-filelist ... --> tag,
# finds all files in the specified folder matching the given regex pattern,
# formats them as a markdown link list, and replaces the content between the tags.
#
# Tag syntax:
#   <!-- start-replace-filelist [folder="./path"] [pattern="regex"] [recursive] [raw] -->
#   ...generated links replaced on each run...
#   <!-- end-replace-filelist -->
#
# Default behaviour (no arguments):
#   Lists ALL non-hidden contents of the README's own directory (files + subdirs),
#   excluding README.md itself. Subdirectory titles are read from their README.md.
#   This produces an augmented navigation + file listing in one block.
#
# Parameters:
#   folder="./path"  — folder to scan (default: directory of the README)
#   pattern="regex"  — filter filenames by regex (default: list everything)
#   recursive        — also descend into subdirectories
#   raw              — use bare filenames instead of Title Case link text
#
# Examples:
#   <!-- start-replace-filelist -->
#   <!-- start-replace-filelist folder="./export" pattern="\.stl$" -->

set -euo pipefail
shopt -s nullglob

EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh")

# Files always excluded regardless of mode (hidden files + OS/editor junk + backup files)
# Build as a find expression: "! -name X ! -name Y ..."
EXCLUDED_FILES_EXPR=(! -name '.*' ! -name 'README.md'
    ! -name 'Thumbs.db' ! -name 'desktop.ini' ! -name '*.tmp'
    ! -name '*.swp' ! -name '*.swo' ! -name '*~'
    ! -name '*.FCBak' ! -name '*.bak' ! -name '*.BAK')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${1:-$(dirname "$SCRIPT_DIR")}"

# Format a filename into readable title-case link text
format_link_text() {
    local filename="$1"
    filename="${filename%.*}"    # strip extension
    filename="${filename//-/ }"  # dashes → spaces
    filename="${filename//_/ }"  # underscores → spaces
    echo "$filename" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1'
}

# Compute path of $1 relative to directory $2 — Python for cross-platform / macOS-safe
relative_path() {
    python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

process_links_for_readme() {
    local readme_path="$1"
    local readme_dir
    readme_dir="$(cd "$(dirname "$readme_path")" && pwd)"

    grep -q "<!-- start-replace-filelist" "$readme_path" || return 0

    echo "Processing links in: $readme_path"

    # Collect all start-tag line numbers; process bottom-to-top so replacements
    # don't shift the line numbers of earlier (higher) blocks.
    local start_lines=()
    while IFS= read -r ln; do
        start_lines+=("$ln")
    done < <(grep -n "<!-- start-replace-filelist" "$readme_path" | cut -d: -f1)

    local i
    for (( i=${#start_lines[@]}-1; i>=0; i-- )); do
        local start_line="${start_lines[$i]}"

        # Find the first end tag that appears after this start tag
        local end_line
        end_line="$(awk -v s="$start_line" \
            'NR>s && /<!-- end-replace-filelist -->/{print NR; exit}' "$readme_path")"

        if [[ -z "$end_line" ]]; then
            echo "  Warning: start tag at line $start_line has no matching end tag, skipping."
            continue
        fi

        local start_tag
        start_tag="$(sed -n "${start_line}p" "$readme_path")"

        # Extract folder= (double- or single-quoted)
        local folder=""
        if [[ "$start_tag" =~ folder=\"([^\"]+)\" ]]; then
            folder="${BASH_REMATCH[1]}"
        elif [[ "$start_tag" =~ folder=\'([^\']+)\' ]]; then
            folder="${BASH_REMATCH[1]}"
        fi

        # Extract pattern= (double- or single-quoted)
        local pattern=""
        if [[ "$start_tag" =~ pattern=\"([^\"]+)\" ]]; then
            pattern="${BASH_REMATCH[1]}"
        elif [[ "$start_tag" =~ pattern=\'([^\']+)\' ]]; then
            pattern="${BASH_REMATCH[1]}"
        fi

        # Default mode: no folder and no pattern → list README's own directory
        local default_mode=false
        [[ -z "$folder" && -z "$pattern" ]] && default_mode=true

        # Resolve folder
        local abs_folder
        if [[ -z "$folder" ]]; then
            abs_folder="$readme_dir"
            folder="."
        elif [[ "$folder" = /* ]]; then
            abs_folder="$folder"
        else
            abs_folder="$readme_dir/$folder"
        fi
        abs_folder="$(cd "$abs_folder" 2>/dev/null && pwd)" || {
            echo "  Warning: folder not found: '$folder' (line $start_line), skipping."
            continue
        }

        local recursive=false raw=false
        [[ "$start_tag" == *"recursive"* ]] && recursive=true
        [[ "$start_tag" == *"raw"* ]]       && raw=true

        echo "  block line $start_line: folder=$folder  pattern=$pattern  recursive=$recursive  raw=$raw  default_mode=$default_mode"

        local find_files="" find_dirs="" find_files_only=""
        local depth_min="-mindepth 1"
        local depth_max="-maxdepth 1"
        # When recursive, drop the maxdepth cap
        if [[ "$recursive" == true ]]; then
            depth_max=""
        fi

        if [[ -z "$pattern" ]]; then
            # No pattern (default or folder-only): dirs first, then files
            # shellcheck disable=SC2086
            find_dirs="$(find "$abs_folder" $depth_min $depth_max -type d "${EXCLUDED_FILES_EXPR[@]}" | sort || true)"
            # shellcheck disable=SC2086
            find_files_only="$(find "$abs_folder" $depth_min $depth_max -type f "${EXCLUDED_FILES_EXPR[@]}" | sort || true)"
            find_files="$(printf '%s\n%s' "$find_dirs" "$find_files_only" | grep -v '^$' || true)"
        else
            # Explicit pattern: files only, filtered by regex
            # shellcheck disable=SC2086
            find_files="$(find "$abs_folder" $depth_min $depth_max -type f "${EXCLUDED_FILES_EXPR[@]}" \
                | grep -E "$pattern" | sort || true)"
        fi

        # Build the markdown link list
        local link_content=""
        while IFS= read -r filepath; do
            [[ -z "$filepath" ]] && continue
            local filename rel_path link_text
            filename="$(basename "$filepath")"
            rel_path="$(relative_path "$filepath" "$readme_dir")"
            rel_path="${rel_path// /%20}"   # encode spaces for markdown URLs
            if [[ -d "$filepath" ]]; then
                if [[ "$raw" == true ]]; then
                    link_text="$filename"
                elif [[ -f "$filepath/README.md" ]]; then
                    link_text="$(grep -m1 '^# ' "$filepath/README.md" | sed 's/^# //')"
                    [[ -z "$link_text" ]] && link_text="$(format_link_text "$filename")"
                else
                    link_text="$(format_link_text "$filename")"
                fi
                link_content+="- [${link_text}](./${rel_path}/)"$'\n'
            else
                local ext
                ext="$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')"
                if [[ "$raw" == true ]]; then
                    link_text="$filename"
                else
                    link_text="$(format_link_text "$filename")"
                fi
                case "$ext" in
                    jpg|jpeg|png|gif|svg|webp|avif)
                        link_content+="- ![${link_text}](./${rel_path})"$'\n'
                        ;;
                    *)
                        link_content+="- [${link_text}](./${rel_path})"$'\n'
                        ;;
                esac
            fi
        done <<< "$find_files"

        # Replace content between tags in the file (bottom-up pass keeps line numbers stable)
        {
            sed -n "1,${start_line}p" "$readme_path"
            [[ -n "$link_content" ]] && printf "%s" "$link_content"
            sed -n "${end_line},\$p" "$readme_path"
        } > "$readme_path.tmp"
        mv "$readme_path.tmp" "$readme_path"

        echo "  ✓ block updated (lines ${start_line}-${end_line})"
    done

    echo "✅ Links updated in $readme_path"
}

process_links_recursively() {
    local dir_path="${1%/}"

    [[ -f "$dir_path/README.md" ]] && process_links_for_readme "$dir_path/README.md"

    for subdir in "$dir_path"/*/; do
        [[ -d "$subdir" ]] || continue
        subdir="${subdir%/}"
        local base_dir
        base_dir="$(basename "$subdir")"
        [[ " ${EXCLUDED_DIRS[*]} " =~ " ${base_dir} " ]] || process_links_recursively "$subdir"
    done
}

process_links_recursively "$ROOT_DIR"
