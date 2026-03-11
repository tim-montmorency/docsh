#!/bin/bash
# docsh/50_generate_frontmatter_content.sh
#
# Scans subdirectory README.md files for YAML frontmatter, then generates
# formatted Markdown content between comment tags.  Follows the same
# replace-between-tags convention as the other docsh scripts.
#
# ── Tag syntax ──────────────────────────────────────────────────────────────
#
#   <!-- start-replace-frontmatter [options] -->
#   <!-- end-replace-frontmatter -->
#
# ── Options ─────────────────────────────────────────────────────────────────
#
#   dir="./path"
#       Directory to scan for subdirectories (relative to the README that
#       contains the tag).  Defaults to the README's own directory.
#
#   filter="key=value"
#       Only include entries where the frontmatter field `key` equals `value`.
#       Example: filter="frontpage=1"
#
#   sort="field"
#       Sort entries by this frontmatter field.  Numeric fields are sorted
#       descending; non-numeric fields are sorted ascending alphabetically.
#       Example: sort="year_start"
#
#   template="grid|list|table"
#       Output format (default: grid).
#
#       grid  — responsive image grid via docsify-img-grid.
#               Requires _cover.jpg or _cover.png in each subdirectory.
#               Entries without a cover image are skipped.
#               Each cell links to the subdirectory and shows the title
#               as caption (via docsify-img-caption alt text).
#               Output: * [![Title](./dir/name/_cover.jpg)](/dir/name/)
#
#       list  — plain bullet list of links.
#               Output: * [Title](/dir/name/) — subtitle, year_start
#
#       table — Markdown table.  Columns are driven by the `fields` option.
#               Output: | Title | subtitle | year_start |
#
#   fields="field1,field2,…"
#       Comma-separated list of frontmatter fields to include in `list` and
#       `table` templates.  The first field is always used as the link text.
#       Defaults: list → "title,subtitle,year_start"
#                 table → "title,subtitle,year_start,tags"
#       (Ignored for `grid` template.)
#
# ── Examples ────────────────────────────────────────────────────────────────
#
#   Project image grid (frontpage projects, most recent first):
#     <!-- start-replace-frontmatter dir="./projets" filter="frontpage=1" sort="year_start" template="grid" -->
#     <!-- end-replace-frontmatter -->
#
#   Audio list sorted by year:
#     <!-- start-replace-frontmatter dir="./audio/piano" sort="year" template="list" fields="title,year" -->
#     <!-- end-replace-frontmatter -->
#
#   CV table of creations:
#     <!-- start-replace-frontmatter dir="./projets" filter="frontpage=1" sort="year_start" template="table" fields="title,subtitle,tags,year_start" -->
#     <!-- end-replace-frontmatter -->

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Frontmatter helpers ──────────────────────────────────────────────────────

# get_fm_value FILE KEY
# Reads the YAML frontmatter block (between the first two ---) and returns
# the value for KEY, stripping inline comments and surrounding whitespace.
get_fm_value() {
    local file="$1" key="$2"
    awk -v key="$key" '
        /^---/ { fm++; next }
        fm == 1 {
            if (index($0, key ":") == 1) {
                sub("^" key ":[[:space:]]*", "")
                sub("[[:space:]]*#.*", "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                print; exit
            }
        }
        fm >= 2 { exit }
    ' "$file" 2>/dev/null || true
}

# ── File replacement ─────────────────────────────────────────────────────────

# replace_between_tags FILE NEW_CONTENT
# Replaces content between the start and end tags (preserving the tag lines).
replace_between_tags() {
    local file="$1"
    local new_content="$2"

    local start_line end_line
    start_line=$(grep -n "<!-- start-replace-frontmatter" "$file" | cut -d: -f1 | head -1)
    end_line=$(grep -n "<!-- end-replace-frontmatter -->" "$file" | cut -d: -f1 | head -1)

    if [[ -z "$start_line" || -z "$end_line" || "$start_line" -ge "$end_line" ]]; then
        echo "  Skipping $file: invalid or missing tags"
        return
    fi

    local tmp
    tmp=$(mktemp)
    sed -n "1,${start_line}p"    "$file"  >  "$tmp"
    printf "%s\n" "$new_content"          >> "$tmp"
    sed -n "${end_line},\$p"     "$file"  >> "$tmp"
    mv "$tmp" "$file"

    echo "  Updated: $(realpath --relative-to="$REPO_ROOT" "$file" 2>/dev/null || echo "$file")"
}

# ── Template renderers ───────────────────────────────────────────────────────

# render_grid ENTRIES_FILE README_DIR
# ENTRIES_FILE: lines of "sort_key|title|img_rel|link"
render_grid() {
    local entries_file="$1"
    local out=""
    while IFS='|' read -r _key title img link; do
        out+="* [![${title}](${img})](${link})\n"
    done < "$entries_file"
    printf "%b" "$out"
}

# render_list ENTRIES_FILE FIELDS_ARRAY README_FILE
# ENTRIES_FILE: lines of "sort_key|readme_abs_path|link"
render_list() {
    local entries_file="$1"
    local fields_csv="$2"
    local out=""
    IFS=',' read -ra fields <<< "$fields_csv"
    local title_field="${fields[0]:-title}"

    while IFS='|' read -r _key readme_abs link; do
        # First field → link text
        local link_text
        link_text=$(get_fm_value "$readme_abs" "$title_field")
        [[ -z "$link_text" ]] && link_text="$(basename "$(dirname "$readme_abs")")"

        # Remaining fields → inline metadata
        local meta_parts=()
        for ((i=1; i<${#fields[@]}; i++)); do
            local val
            val=$(get_fm_value "$readme_abs" "${fields[$i]}")
            [[ -n "$val" ]] && meta_parts+=("$val")
        done

        local entry="* [${link_text}](${link})"
        if [[ ${#meta_parts[@]} -gt 0 ]]; then
            local joined
            printf -v joined ' — %s' "${meta_parts[@]}"
            entry+="${joined# — }"   # trim leading " — "
            # re-add with proper separator
            entry="* [${link_text}](${link}) — $(IFS=' — '; echo "${meta_parts[*]}")"
        fi
        out+="${entry}\n"
    done < "$entries_file"
    printf "%b" "$out"
}

# render_table ENTRIES_FILE FIELDS_CSV
# ENTRIES_FILE: lines of "sort_key|readme_abs_path|link"
render_table() {
    local entries_file="$1"
    local fields_csv="$2"
    IFS=',' read -ra fields <<< "$fields_csv"
    local title_field="${fields[0]:-title}"

    # Build header
    local header="| "
    local sep="| "
    for f in "${fields[@]}"; do
        # Capitalise first letter of field name for header
        local hdr="${f^}"
        header+="${hdr} | "
        sep+="--- | "
    done

    local out="${header}\n${sep}\n"

    while IFS='|' read -r _key readme_abs link; do
        local row="| "
        local first=1
        for f in "${fields[@]}"; do
            local val
            val=$(get_fm_value "$readme_abs" "$f")
            [[ -z "$val" ]] && val=""
            if [[ $first -eq 1 ]]; then
                local display="$val"
                [[ -z "$display" ]] && display="$(basename "$(dirname "$readme_abs")")"
                row+="[${display}](${link}) | "
                first=0
            else
                row+="${val} | "
            fi
        done
        out+="${row}\n"
    done < "$entries_file"

    printf "%b" "$out"
}

# ── Entry collector ──────────────────────────────────────────────────────────

# collect_entries SCAN_DIR FILTER_OPT SORT_OPT README_DIR TEMPLATE
# Writes to stdout: lines of the form needed by the chosen renderer.
# For grid:  "sort_val|title|img_rel|link"
# For list/table: "sort_val|readme_abs|link"
collect_entries() {
    local scan_dir="$1"
    local filter_opt="$2"
    local sort_opt="$3"
    local readme_dir="$4"
    local tmpl="$5"

    local tmp_entries
    tmp_entries=$(mktemp)

    for subdir in "$scan_dir"/*/; do
        [[ ! -d "$subdir" ]] && continue
        subdir="${subdir%/}"
        local sub_readme="${subdir}/README.md"
        [[ ! -f "$sub_readme" ]] && continue

        # filter
        if [[ -n "$filter_opt" ]]; then
            local fk fv fval
            fk="${filter_opt%%=*}"
            fv="${filter_opt#*=}"
            fval=$(get_fm_value "$sub_readme" "$fk")
            [[ "$fval" != "$fv" ]] && continue
        fi

        # sort key
        local sort_val="0"
        if [[ -n "$sort_opt" ]]; then
            sort_val=$(get_fm_value "$sub_readme" "$sort_opt") || sort_val="0"
        fi
        [[ -z "$sort_val" ]] && sort_val="0"

        # absolute path
        local sub_abs
        sub_abs="$(cd "$subdir" && pwd)"

        # Docsify link (absolute from site root)
        local rel_from_root
        rel_from_root=$(realpath --relative-to="$REPO_ROOT" "$sub_abs" 2>/dev/null || echo "${sub_abs#$REPO_ROOT/}")
        local link="/${rel_from_root}/"

        if [[ "$tmpl" == "grid" ]]; then
            local img_rel=""
            local rel_from_readme="${sub_abs#${readme_dir}/}"
            if [[ -f "${sub_abs}/_cover.jpg" ]]; then
                img_rel="./${rel_from_readme}/_cover.jpg"
            elif [[ -f "${sub_abs}/_cover.png" ]]; then
                img_rel="./${rel_from_readme}/_cover.png"
            else
                continue   # grid requires cover image
            fi
            local title
            title=$(get_fm_value "$sub_readme" "title")
            [[ -z "$title" ]] && title="$(basename "$subdir")"
            printf '%s|%s|%s|%s\n' "$sort_val" "$title" "$img_rel" "$link" >> "$tmp_entries"
        else
            printf '%s|%s|%s\n' "$sort_val" "$sub_readme" "$link" >> "$tmp_entries"
        fi
    done

    # Sort: if sort_val is purely numeric use numeric desc, else alphabetic asc
    if [[ -n "$sort_opt" ]]; then
        local first_val
        first_val=$(head -1 "$tmp_entries" | cut -d'|' -f1)
        if [[ "$first_val" =~ ^[0-9]+$ ]]; then
            sort -t'|' -k1 -rn "$tmp_entries" -o "$tmp_entries"
        else
            sort -t'|' -k1 "$tmp_entries" -o "$tmp_entries"
        fi
    fi

    cat "$tmp_entries"
    rm -f "$tmp_entries"
}

# ── Main per-readme processor ────────────────────────────────────────────────

process_readme() {
    local readme="$1"
    local readme_dir
    readme_dir="$(cd "$(dirname "$readme")" && pwd)"

    # Read the start tag line
    local start_tag
    start_tag=$(grep "<!-- start-replace-frontmatter" "$readme" | head -1)

    # Parse options from tag
    local dir_opt filter_opt sort_opt tmpl fields_opt
    dir_opt=$(    echo "$start_tag" | grep -oE 'dir="[^"]*"'     | sed 's/dir="//;s/"//'     || true)
    filter_opt=$( echo "$start_tag" | grep -oE 'filter="[^"]*"'  | sed 's/filter="//;s/"//'  || true)
    sort_opt=$(   echo "$start_tag" | grep -oE 'sort="[^"]*"'    | sed 's/sort="//;s/"//'    || true)
    tmpl=$(       echo "$start_tag" | grep -oE 'template="[^"]*"'| sed 's/template="//;s/"//'|| true)
    fields_opt=$( echo "$start_tag" | grep -oE 'fields="[^"]*"'  | sed 's/fields="//;s/"//'  || true)

    # Defaults
    [[ -z "$tmpl" ]] && tmpl="grid"
    if [[ -z "$fields_opt" ]]; then
        [[ "$tmpl" == "table" ]] && fields_opt="title,subtitle,year_start,tags" \
                                 || fields_opt="title,subtitle,year_start"
    fi

    # Resolve scan directory
    local scan_dir
    if [[ -n "$dir_opt" ]]; then
        scan_dir="${readme_dir}/${dir_opt}"
        scan_dir="$(cd "$scan_dir" 2>/dev/null && pwd || echo "")"
    else
        scan_dir="$readme_dir"
    fi

    if [[ -z "$scan_dir" || ! -d "$scan_dir" ]]; then
        echo "  Skipping $readme: scan dir '${dir_opt:-$readme_dir}' not found"
        return
    fi

    # Collect
    local tmp_entries
    tmp_entries=$(mktemp)
    collect_entries "$scan_dir" "$filter_opt" "$sort_opt" "$readme_dir" "$tmpl" > "$tmp_entries"

    if [[ ! -s "$tmp_entries" ]]; then
        echo "  No entries found in $scan_dir (filter='$filter_opt', template='$tmpl')"
        rm -f "$tmp_entries"
        return
    fi

    # Render
    local content=""
    case "$tmpl" in
        grid)  content=$(render_grid  "$tmp_entries" "$readme_dir") ;;
        list)  content=$(render_list  "$tmp_entries" "$fields_opt") ;;
        table) content=$(render_table "$tmp_entries" "$fields_opt") ;;
        *)
            echo "  Unknown template '$tmpl' — defaulting to grid"
            content=$(render_grid "$tmp_entries" "$readme_dir")
            ;;
    esac
    rm -f "$tmp_entries"

    replace_between_tags "$readme" "$content"
}

# ── Walk ─────────────────────────────────────────────────────────────────────

EXCLUDED=(".git" "node_modules" "__pycache__" "docsh" "vendor" "_site")

echo "Generating frontmatter content…"

while IFS= read -r readme; do
    skip=0
    for ex in "${EXCLUDED[@]}"; do
        [[ "$readme" == *"/${ex}/"* ]] && skip=1 && break
    done
    [[ $skip -eq 1 ]] && continue

    if grep -q "<!-- start-replace-frontmatter" "$readme" 2>/dev/null; then
        echo "Processing: $(realpath --relative-to="$REPO_ROOT" "$readme" 2>/dev/null || echo "$readme")"
        process_readme "$readme"
    fi
done < <(find "$REPO_ROOT" -name "README.md" -not -path "*/.git/*")

echo "Frontmatter content generation complete."
