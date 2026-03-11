#!/bin/bash
# docsh/75_generate_navbar.sh
#
# Generates Docsify _navbar.md content.
# If no _navbar.md exists in the repo root, one is created.
#
# ── Two modes ────────────────────────────────────────────────────────────────
#
#  TAG MODE    If _navbar.md contains a start-replace-navbar tag, only the
#              content between the tags is replaced (preserves surrounding text).
#              Options are read inline from the opening tag.
#
#  CREATE MODE If no _navbar.md is found, a new one is generated at repo root.
#
# ── Tag syntax ───────────────────────────────────────────────────────────────
#
#   <!-- start-replace-navbar [options] -->
#   <!-- end-replace-navbar -->
#
# ── Options (inline inside the opening tag) ──────────────────────────────────
#
#   dir="./path"        Directory to scan, relative to the _navbar.md.
#                       Default: the navbar file's own directory.
#
#   maxdepth="N"        Stop recursing after N levels.  1 = immediate children
#                       only.  Default: 1 (navbar is typically shallow).
#
#   filter="key=value"  Only include entries whose frontmatter field `key`
#                       equals `value`.  Applied on top of the global rule.
#                       Example: filter="frontpage=1"
#
#   sort="field"        Sort siblings by this frontmatter field.
#                       Numeric values → descending; text → ascending.
#
# ── Global frontpage rule ────────────────────────────────────────────────────
#
#   frontpage: 0  in a README's YAML frontmatter → that directory is silently
#   skipped in every navbar, in both modes.  Any other value (1, missing) is
#   included normally.
#

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh" "vendor" "_site")

# ── Frontmatter helpers ───────────────────────────────────────────────────────

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

get_title() {
    local file="$1"
    local t
    t=$(grep -m1 "^# " "$file" 2>/dev/null | sed 's/^# //' || true)
    [[ -z "$t" ]] && t=$(get_fm_value "$file" "title")
    [[ -z "$t" ]] && t=$(basename "$(dirname "$file")")
    printf '%s' "$t"
}

get_tooltip() {
    local file="$1" title="$2"
    local t
    t=$(get_fm_value "$file" "shortname")
    [[ -z "$t" ]] && t=$(get_fm_value "$file" "description")
    [[ -z "$t" ]] && t="$title"
    printf '%s' "$t"
}

should_skip() {
    local fp hid
    fp=$(get_fm_value "$1" "frontpage")
    [[ "$fp" == "0" ]] && return 0
    hid=$(get_fm_value "$1" "hidden")
    [[ "$hid" == "1" ]]
}

dir_link() {
    local rel="${1#$REPO_ROOT}"
    rel="${rel#/}"; rel="${rel%/}"
    [[ -z "$rel" ]] && rel="/" || rel="/$rel/"
    printf '%s' "$(printf '%s' "$rel" | sed -E 's:/{2,}:/:g')"
}

# ── Tag replacement ───────────────────────────────────────────────────────────

replace_between_tags() {
    local file="$1" new_content="$2"
    local start_line end_line

    start_line=$(grep -n "<!-- start-replace-navbar" "$file" | cut -d: -f1 | head -1)
    end_line=$(  grep -n "<!-- end-replace-navbar -->"       "$file" | cut -d: -f1 | head -1)

    if [[ -z "$start_line" || -z "$end_line" || "$start_line" -ge "$end_line" ]]; then
        echo "  Skipping: missing or invalid tags in $file" >&2
        return 1
    fi

    local tmp
    tmp=$(mktemp)
    sed -n "1,${start_line}p" "$file" >  "$tmp"
    printf "%s\n" "$new_content"       >> "$tmp"
    sed -n "${end_line},\$p"  "$file"  >> "$tmp"
    mv "$tmp" "$file"
}

# ── Walker (one level only by default for navbar) ────────────────────────────
#
# walk_navbar OUTFILE DIR DEPTH MAXDEPTH FILTER SORT_FIELD
#
# Appends "* [Title](/path/)" for each qualifying child of DIR.

walk_navbar() {
    local outfile="$1" dir="$2" depth="$3"
    local maxdepth="$4" filter="$5" sort_field="$6"

    local tmp_kids
    tmp_kids=$(mktemp)

    for subdir in "$dir"/*/; do
        [[ ! -d "$subdir" ]] && continue
        local base; base=$(basename "${subdir%/}")
        [[ " ${EXCLUDED_DIRS[*]} " =~ " ${base} " ]] && continue
        [[ -f "${subdir}.docshignore" ]]  && continue
        [[ ! -f "${subdir}README.md" ]]   && continue

        local readme="${subdir}README.md"

        # Global opt-out
        should_skip "$readme" && continue

        # Inline filter (opt-in)
        if [[ -n "$filter" ]]; then
            local fk fv fval
            fk="${filter%%=*}"; fv="${filter#*=}"
            fval=$(get_fm_value "$readme" "$fk")
            [[ "$fval" != "$fv" ]] && continue
        fi

        local sv="0"
        if [[ -n "$sort_field" ]]; then
            sv=$(get_fm_value "$readme" "$sort_field") || sv="0"
            [[ -z "$sv" ]] && sv="0"
        fi
        printf '%s\t%s\n' "$sv" "${subdir%/}" >> "$tmp_kids"
    done

    if [[ -s "$tmp_kids" && -n "$sort_field" ]]; then
        local fv; fv=$(head -1 "$tmp_kids" | cut -f1)
        if [[ "$fv" =~ ^-?[0-9]+$ ]]; then
            sort -t$'\t' -k1,1rn -k2,2 "$tmp_kids" -o "$tmp_kids"
        else
            sort -t$'\t' -k1,1  -k2,2  "$tmp_kids" -o "$tmp_kids"
        fi
    fi

    while IFS=$'\t' read -r _ child; do
        local readme="$child/README.md"
        local title; title=$(get_title "$readme")
        local tooltip; tooltip=$(get_tooltip "$readme" "$title")
        local link;  link=$(dir_link "$child")

        # Embed _icon.svg as base64 data URI if present (grey; active color applied at runtime by JS)
        local icon_path="$child/_icon.svg"
        if [[ -f "$icon_path" ]]; then
            local icon_b64; icon_b64=$(base64 -i "$icon_path" | tr -d '\n')
            printf '* [![%s](data:image/svg+xml;base64,%s)](%s "%s")\n' \
                "$title" "$icon_b64" "$link" "$tooltip" >> "$outfile"
            echo "  Added (icon): $link  ($title)"
        else
            printf '* [%s](%s "%s")\n' "$title" "$link" "$tooltip" >> "$outfile"
            echo "  Added: $link  ($title)"
        fi

        # Recurse if not at maxdepth
        if [[ -z "$maxdepth" || "$depth" -lt "$maxdepth" ]]; then
            local sub_tmp; sub_tmp=$(mktemp)
            walk_navbar "$sub_tmp" "$child" "$((depth+1))" \
                "$maxdepth" "$filter" "$sort_field"
            if [[ -s "$sub_tmp" ]]; then
                # Indent sub-items two spaces
                sed 's/^/  /' "$sub_tmp" >> "$outfile"
            fi
            rm -f "$sub_tmp"
        fi
    done < "$tmp_kids"

    rm -f "$tmp_kids"
}

# ── Tag-mode processor ────────────────────────────────────────────────────────

process_tagged_navbar() {
    local navbar="$1"
    local navbar_dir
    navbar_dir="$(cd "$(dirname "$navbar")" && pwd)"

    local tag
    tag=$(grep "<!-- start-replace-navbar" "$navbar" | head -1)

    local dir_opt maxdepth_opt filter_opt sort_opt
    dir_opt=$(      echo "$tag" | grep -oE 'dir="[^"]*"'      | sed 's/dir="//;s/"//'      || true)
    maxdepth_opt=$( echo "$tag" | grep -oE 'maxdepth="[^"]*"' | sed 's/maxdepth="//;s/"//' || true)
    filter_opt=$(   echo "$tag" | grep -oE 'filter="[^"]*"'   | sed 's/filter="//;s/"//'   || true)
    sort_opt=$(     echo "$tag" | grep -oE 'sort="[^"]*"'     | sed 's/sort="//;s/"//'     || true)
    [[ -z "$maxdepth_opt" ]] && maxdepth_opt="1"
    [[ -z "$filter_opt"   ]] && filter_opt="navbar=1"

    local scan_dir="$navbar_dir"
    if [[ -n "$dir_opt" ]]; then
        scan_dir="$(cd "${navbar_dir}/${dir_opt}" 2>/dev/null && pwd || echo "")"
    fi

    if [[ -z "$scan_dir" || ! -d "$scan_dir" ]]; then
        echo "  Skipping: dir '${dir_opt}' not found in $navbar" >&2
        return 0
    fi

    local tmp_out
    tmp_out=$(mktemp)

    # Emit the scan_dir itself first if its README qualifies
    local self_readme="$scan_dir/README.md"
    if [[ -f "$self_readme" ]]; then
        local self_nav; self_nav=$(get_fm_value "$self_readme" "navbar")
        if [[ "$self_nav" == "1" ]]; then
            local self_title; self_title=$(get_title "$self_readme")
            local self_tooltip; self_tooltip=$(get_tooltip "$self_readme" "$self_title")
            local self_link; self_link=$(dir_link "$scan_dir")
            local self_icon="$scan_dir/_icon.svg"
            if [[ -f "$self_icon" ]]; then
                local sg_b64; sg_b64=$(base64 -i "$self_icon" | tr -d '\n')
                printf '* [![%s](data:image/svg+xml;base64,%s)](%s "%s")\n' \
                    "$self_title" "$sg_b64" "$self_link" "$self_tooltip" >> "$tmp_out"
                echo "  Added (icon, self): $self_link  ($self_title)"
            else
                printf '* [%s](%s "%s")\n' "$self_title" "$self_link" "$self_tooltip" >> "$tmp_out"
                echo "  Added (self): $self_link  ($self_title)"
            fi
        fi
    fi

    walk_navbar "$tmp_out" "$scan_dir" "1" \
        "$maxdepth_opt" "$filter_opt" "$sort_opt"

    if [[ ! -s "$tmp_out" ]]; then
        echo "  No entries found for $(realpath --relative-to="$REPO_ROOT" "$navbar" 2>/dev/null || echo "$navbar")"
        rm -f "$tmp_out"
        return 0
    fi

    replace_between_tags "$navbar" "$(cat "$tmp_out")"
    rm -f "$tmp_out"
    echo "  Updated: $(realpath --relative-to="$REPO_ROOT" "$navbar" 2>/dev/null || echo "$navbar")"
}

# ── Create mode: generate a new _navbar.md at repo root ──────────────────────

create_navbar() {
    local navbar_file="$1"

    local tmp_out
    tmp_out=$(mktemp)
    walk_navbar "$tmp_out" "$REPO_ROOT" "1" "1" "navbar=1" ""

    {
        printf "<!-- Generated by docsh/75_generate_navbar.sh on %s -->\n" \
            "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf "<!-- start-replace-navbar maxdepth=\"1\" -->\n"
        cat "$tmp_out"
        printf "<!-- end-replace-navbar -->\n"
    } > "$navbar_file"

    rm -f "$tmp_out"
    echo "Created: $navbar_file"
}

# ── Entry point ───────────────────────────────────────────────────────────────

echo "Generating navbar content…"

# Find existing _navbar.md files
navbars=()
while IFS= read -r f; do
    navbars+=("$f")
done < <(find "$REPO_ROOT" -name "_navbar.md" \
    -not -path "*/.git/*"         \
    -not -path "*/docsh/*"        \
    -not -path "*/vendor/*"       \
    -not -path "*/_site/*"        \
    -not -path "*/node_modules/*")

if [[ "${#navbars[@]}" -eq 0 ]]; then
    echo "No _navbar.md found — creating one at repo root…"
    create_navbar "$REPO_ROOT/_navbar.md"
else
    for navbar in "${navbars[@]}"; do
        if grep -q "<!-- start-replace-navbar" "$navbar" 2>/dev/null; then
            echo "Processing: $(realpath --relative-to="$REPO_ROOT" "$navbar" 2>/dev/null || echo "$navbar")"
            process_tagged_navbar "$navbar"
        else
            echo "Skipping (no tags): $(realpath --relative-to="$REPO_ROOT" "$navbar" 2>/dev/null || echo "$navbar")"
        fi
    done
fi

echo "Navbar generation complete."
