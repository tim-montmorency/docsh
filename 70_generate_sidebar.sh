#!/bin/bash
# docsh/70_generate_sidebar.sh — Generate Docsify _sidebar.md files.
#
# Walks the repository tree and generates sidebar navigation content.
#
# ── Two modes ────────────────────────────────────────────────────────────────
#
#  TAG MODE    If _sidebar.md contains a start-replace-sidebar tag, only the
#              content between the tags is replaced (preserves surrounding text).
#              Options are read inline from the opening tag.
#
#  LEGACY MODE If _sidebar.md has no such tag, the whole file is rewritten
#              (backward-compatible with the previous behaviour).
#
# ── Tag syntax ───────────────────────────────────────────────────────────────
#
#   <!-- start-replace-sidebar [options] -->
#   <!-- end-replace-sidebar -->
#
# ── Options (inline inside the opening tag) ──────────────────────────────────
#
#   dir="./path"        Directory to scan, relative to the _sidebar.md.
#                       Default: the sidebar file's own directory.
#
#   maxdepth="N"        Stop recursing after N levels.  1 = immediate children
#                       only.  Default: unlimited.
#
#   filter="key=value"  Only include entries whose frontmatter field `key`
#                       equals `value`.  Applied on top of the global rule.
#                       Example: filter="frontpage=1"
#
#   sort="field"        Sort siblings by this frontmatter field.
#                       Numeric values → descending; text → ascending.
#
#   flat="true"         Emit a flat non-indented list.  Default: false.
#
# ── Global frontpage rule ────────────────────────────────────────────────────
#
#   frontpage: 0  in a README's YAML frontmatter → that directory is silently
#   skipped in every sidebar, in both modes.  Any other value (1, missing) is
#   included normally.
#
# ── Legacy CLI flags (legacy mode only) ──────────────────────────────────────
#
#   -r, --include-root   Include the repo-root README as the first entry.
#

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/lib/docsh_lib.sh"

# ── Recursive walker ─────────────────────────────────────────────────────────
#
# walk OUTFILE DIR INDENT DEPTH MAXDEPTH FILTER SORT_FIELD FLAT
#
# Appends "INDENT* [Title](/path/)" to OUTFILE for DIR (if it passes all
# checks), then recurses into sorted subdirectories.

walk() {
    local outfile="$1" dir="$2" indent="$3" depth="$4"
    local maxdepth="$5" filter="$6" sort_field="$7" flat="$8"

    [[ -f "$dir/.docshignore" ]] && return 0

    local readme="$dir/README.md"
    [[ ! -f "$readme" ]] && return 0

    # Global opt-out rule
    should_skip "$readme" && return 0

    # Inline filter (opt-in)
    if [[ -n "$filter" ]]; then
        local fk fv fval
        fk="${filter%%=*}"; fv="${filter#*=}"
        fval=$(get_fm_value "$readme" "$fk")
        [[ "$fval" != "$fv" ]] && return 0
    fi

    printf '%s* [%s](%s)\n' "$indent" "$(get_title "$readme")" "$(dir_link "$dir")" >> "$outfile"
    echo "  Added: $(dir_link "$dir")  ($(get_title "$readme"))"

    # Depth limit
    [[ -n "$maxdepth" && "$depth" -ge "$maxdepth" ]] && return 0

    local child_indent
    [[ "$flat" == "true" ]] && child_indent="" || child_indent="  ${indent}"

    _walk_children "$outfile" "$dir" "$child_indent" "$((depth+1))" \
        "$maxdepth" "$filter" "$sort_field" "$flat"
}

# _walk_children OUTFILE DIR INDENT DEPTH MAXDEPTH FILTER SORT_FIELD FLAT
_walk_children() {
    local outfile="$1" dir="$2" indent="$3" depth="$4"
    local maxdepth="$5" filter="$6" sort_field="$7" flat="$8"

    local tmp_kids
    tmp_kids=$(mktemp)

    for subdir in "$dir"/*/; do
        [[ ! -d "$subdir" ]] && continue
        local base; base=$(basename "${subdir%/}")
        [[ " ${EXCLUDED_DIRS[*]} " =~ " ${base} " ]] && continue
        [[ -f "${subdir}.docshignore" ]]  && continue
        [[ ! -f "${subdir}README.md" ]]   && continue

        local sv="0"
        if [[ -n "$sort_field" ]]; then
            sv=$(get_fm_value "${subdir}README.md" "$sort_field") || sv="0"
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
        walk "$outfile" "$child" "$indent" "$depth" \
             "$maxdepth" "$filter" "$sort_field" "$flat"
    done < "$tmp_kids"

    rm -f "$tmp_kids"
}

# ── Tag-mode processor ────────────────────────────────────────────────────────

process_tagged_sidebar() {
    local sidebar="$1"
    local sidebar_dir
    sidebar_dir="$(cd "$(dirname "$sidebar")" && pwd)"

    local tag
    tag=$(grep "<!-- start-replace-sidebar" "$sidebar" | head -1)

    local dir_opt maxdepth_opt filter_opt sort_opt flat_opt
    dir_opt=$(      echo "$tag" | grep -oE 'dir="[^"]*"'      | sed 's/dir="//;s/"//'      || true)
    maxdepth_opt=$( echo "$tag" | grep -oE 'maxdepth="[^"]*"' | sed 's/maxdepth="//;s/"//' || true)
    filter_opt=$(   echo "$tag" | grep -oE 'filter="[^"]*"'   | sed 's/filter="//;s/"//'   || true)
    sort_opt=$(     echo "$tag" | grep -oE 'sort="[^"]*"'     | sed 's/sort="//;s/"//'     || true)
    flat_opt=$(     echo "$tag" | grep -oE 'flat="[^"]*"'     | sed 's/flat="//;s/"//'     || true)
    [[ -z "$flat_opt" ]] && flat_opt="false"

    local scan_dir="$sidebar_dir"
    if [[ -n "$dir_opt" ]]; then
        scan_dir="$(cd "${sidebar_dir}/${dir_opt}" 2>/dev/null && pwd || echo "")"
    fi

    if [[ -z "$scan_dir" || ! -d "$scan_dir" ]]; then
        echo "  Skipping: dir '${dir_opt}' not found in $sidebar" >&2
        return 0
    fi

    local tmp_out
    tmp_out=$(mktemp)

    _walk_children "$tmp_out" "$scan_dir" "" "1" \
        "$maxdepth_opt" "$filter_opt" "$sort_opt" "$flat_opt"

    if [[ ! -s "$tmp_out" ]]; then
        echo "  No entries found for ${sidebar#${REPO_ROOT}/}"
        rm -f "$tmp_out"
        return 0
    fi

    replace_between_tags "$sidebar" "sidebar" "$(cat "$tmp_out")"
    rm -f "$tmp_out"
}

# ── Legacy full-file rewrite ──────────────────────────────────────────────────

legacy_generate() {
    local sidebar_file="$1" include_root="$2"

    > "$sidebar_file"
    printf "<!-- Generated by docsh/70_generate_sidebar.sh on %s -->\n" \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$sidebar_file"
    printf "<!-- include_root=%s -->\n\n" "$include_root" >> "$sidebar_file"

    local tmp_out
    tmp_out=$(mktemp)
    if [[ "$include_root" == "true" ]]; then
        walk "$tmp_out" "$REPO_ROOT" "" "0" "" "" "" "false"
    else
        _walk_children "$tmp_out" "$REPO_ROOT" "" "1" "" "" "" "false"
    fi
    cat "$tmp_out" >> "$sidebar_file"
    rm -f "$tmp_out"

    echo "Sidebar generation complete: $sidebar_file"
}

# ── Entry point ───────────────────────────────────────────────────────────────

echo "Generating sidebar content…"

# Build -not -path exclusions for every git submodule path so that
# _sidebar.md files belonging to submodules are never touched when this
# script is run from a parent repository.
SUBMODULE_EXCLUDES=()
if [[ -f "$REPO_ROOT/.gitmodules" ]]; then
    while IFS= read -r sm_path; do
        [[ -n "$sm_path" ]] && SUBMODULE_EXCLUDES+=(-not -path "${REPO_ROOT}/${sm_path}/*")
    done < <(git -C "$REPO_ROOT" config --file "$REPO_ROOT/.gitmodules" \
                 --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
fi

while IFS= read -r sidebar; do
    if grep -q "<!-- start-replace-sidebar" "$sidebar" 2>/dev/null; then
        echo "Processing: ${sidebar#${REPO_ROOT}/}"
        process_tagged_sidebar "$sidebar"
    else
        echo "Processing (legacy): ${sidebar#${REPO_ROOT}/}"
        legacy_generate "$sidebar" "false"
    fi
done < <(find "$REPO_ROOT" -name "_sidebar.md" \
    -not -path "*/.git/*"         \
    -not -path "*/docsh/*"        \
    -not -path "*/vendor/*"       \
    -not -path "*/_site/*"        \
    -not -path "*/node_modules/*" \
    "${SUBMODULE_EXCLUDES[@]}")

echo "Sidebar generation complete."
