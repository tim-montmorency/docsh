#!/bin/bash
# docsh/60_generate_subnav.sh — Generate sub-navigation link lists in README.md files.
#
# For each README.md that contains start/end subnav tags, generates a nested
# Markdown list of immediate subdirectories that have their own README.md.
# Entries show a cover image (_cover.png / _cover.jpg) when present, or a plain
# text link.  Recurses into subdirectories up to the configured depth.
#
# ── Tag syntax ───────────────────────────────────────────────────────────────
#
#   <!-- start-replace-subnav [depth=N] -->
#   <!-- end-replace-subnav -->
#
# ── Attributes ───────────────────────────────────────────────────────────────
#
#   depth=N   Maximum recursion depth (default: unlimited).
#             depth=1 lists only immediate children.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash docsh/60_generate_subnav.sh [DIR]
#     DIR  root of the tree to scan (default: repository root)
#
#   Called automatically by docsh/autorun.sh.

# Fail on error, undefined vars, and fail pipelines; make globs return empty when no match
set -euo pipefail
shopt -s nullglob

# Default to the parent directory of this script (usually the repo root).
# You can still override by passing a root as the first argument.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/lib/docsh_lib.sh"
ROOT_DIR="${1:-$REPO_ROOT}"

echo "Generating subnavs for root: $ROOT_DIR"

# generate_subnav_content DIR INDENT_LEVEL [MAX_DEPTH] [README_DIR]
generate_subnav_content() {
    local parent_dir="$1"
    local indent_level="$2"
    local max_depth="${3:-}"
    local readme_dir="${4:-$parent_dir}"   # directory of the README being generated
    local content_lines=()

    parent_dir="${parent_dir%/}"
    readme_dir="${readme_dir%/}"

    # If max_depth is numeric and we've reached it, stop recursion
    if [[ -n "$max_depth" ]]; then
        # ensure max_depth is numeric
        if ! [[ "$max_depth" =~ ^[0-9]+$ ]]; then
            max_depth=""
        fi
    fi

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
                subdir_title=$(get_title "$subdir_readme")
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
                # Path is relative to the README being generated (readme_dir),
                # so images resolve correctly regardless of nesting depth.
                local img_rel="${subdir#$readme_dir/}"
                img_rel="${img_rel%/}"
                local cover_image=""
                if [[ -f "$subdir/_cover.png" ]]; then
                    cover_image="./${img_rel}/_cover.png"
                elif [[ -f "$subdir/_cover.jpg" ]]; then
                    cover_image="./${img_rel}/_cover.jpg"
                fi
                
                # Create link with image if cover exists, otherwise text link
                if [[ -n "$cover_image" ]]; then
                    content_lines+=("${indent}* [![${subdir_title}](${cover_image})](${link})")
                else
                    content_lines+=("${indent}* [${subdir_title}](${link})")
                fi

                local sub_content
                # Only recurse further if max_depth not set or indent_level+1 < max_depth
                if [[ -z "$max_depth" || $((indent_level + 1)) -lt $max_depth ]]; then
                    sub_content=$(generate_subnav_content "$subdir" $((indent_level + 1)) "$max_depth" "$readme_dir")
                else
                    sub_content=""
                fi
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

# replace_between_tags README_PATH NEW_CONTENT
# Replaces content between subnav tags (preserving tag lines).
replace_between_tags() {
    local readme_path="$1"
    local subnav_content="$2"

    if ! grep -q "<!-- start-replace-subnav" "$readme_path" || ! grep -q "<!-- end-replace-subnav -->" "$readme_path"; then
        return
    fi

    echo "  Processing: ${readme_path#${REPO_ROOT}/}"

    local start_line end_line
    start_line=$(grep -n "<!-- start-replace-subnav" "$readme_path" | cut -d: -f1 | head -n 1)
    end_line=$(grep -n  "<!-- end-replace-subnav -->" "$readme_path" | cut -d: -f1 | head -n 1)

    if [[ -z "$start_line" || -z "$end_line" || $start_line -gt $end_line ]]; then
        echo "Skipping $readme_path, invalid tag order."
        return
    fi

    local tmp
    tmp=$(mktemp)
    sed -n "1,${start_line}p"         "$readme_path" >  "$tmp"
    printf "%s\n" "$subnav_content"                  >> "$tmp"
    sed -n "${end_line},\$p"          "$readme_path" >> "$tmp"
    mv "$tmp" "$readme_path"

    echo "  Updated: ${readme_path#${REPO_ROOT}/}"
}

# Updates the given directory's README.md with subnavigation if README.md exists
generate_readme_in_subfolders() {
    local parent_dir="$1"
    local readme_path="$parent_dir/README.md"

    if [[ ! -f "$readme_path" ]]; then
        return
    fi

    local title
    title=$(get_title "$readme_path")
    [[ -z "$title" ]] && title=$(basename "$parent_dir")

    # Detect optional depth argument in the start tag: <!-- start-replace-subnav depth=N -->
    local start_tag_line
    start_tag_line=$(grep -n "<!-- start-replace-subnav" "$readme_path" | cut -d: -f2- | head -n1 || true)
    local max_depth=""
    if [[ -n "$start_tag_line" ]]; then
        # extract depth=NUMBER
        if [[ $start_tag_line =~ depth=([0-9]+) ]]; then
            max_depth="${BASH_REMATCH[1]}"
        fi
    fi

    local subnav_content
    subnav_content=$(generate_subnav_content "$parent_dir" 0 "$max_depth")

    replace_between_tags "$readme_path" "$subnav_content"
}

# Recursively walk through directories to generate and insert subnav content
generate_subnav() {
    local dir_path="$1"
    dir_path="${dir_path%/}"

    if [[ -f "$dir_path/README.md" ]]; then
        generate_readme_in_subfolders "$dir_path"
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
