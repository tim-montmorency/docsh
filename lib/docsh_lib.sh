#!/bin/bash
# docsh/lib/docsh_lib.sh — Shared helpers sourced by all docsh scripts.
#
# Usage (at the top of every docsh script, after setting SCRIPT_DIR):
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
#   . "$SCRIPT_DIR/lib/docsh_lib.sh"
#
# Provides:
#   REPO_ROOT        — absolute path to the repository root
#   EXCLUDED_DIRS    — canonical array of directory basenames to skip
#   get_fm_value()   — read a single YAML frontmatter key from a file
#   get_title()      — H1 heading → frontmatter title → dirname fallback
#   should_skip()    — true when frontpage:0 or hidden:1
#   dir_link()       — repo-relative Docsify URL for a directory
#   replace_between_tags() — idempotent in-place tag-block replacement

# Guard against double-sourcing
[[ "${_DOCSH_LIB_LOADED:-}" == "1" ]] && return 0
_DOCSH_LIB_LOADED=1

# ── REPO_ROOT ─────────────────────────────────────────────────────────────────
# Derived from this file's own location: docsh/lib/ → docsh/ → repo root
_DOCSH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_DOCSH_LIB_DIR/../.." && pwd)"

# ── Canonical exclusions ─────────────────────────────────────────────────────
# Directory basenames skipped by all traversals.
EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh" "vendor" "_site")

# ── Frontmatter helper ────────────────────────────────────────────────────────
# get_fm_value FILE KEY
# Reads the YAML frontmatter block (between the first two ---) and prints the
# value for KEY, stripping inline comments and surrounding whitespace.
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

# ── Title helper ──────────────────────────────────────────────────────────────
# get_title FILE
# Returns: first H1 heading → frontmatter 'title' field → directory basename
get_title() {
    local file="$1"
    local t
    t=$(grep -m1 "^# " "$file" 2>/dev/null | sed 's/^# //' || true)
    [[ -z "$t" ]] && t=$(get_fm_value "$file" "title")
    [[ -z "$t" ]] && t=$(basename "$(dirname "$file")")
    printf '%s' "$t"
}

# ── Skip predicate ────────────────────────────────────────────────────────────
# should_skip README
# Returns 0 (true) when the entry must be excluded from nav/sidebar output:
#   frontpage: 0  →  skip
#   hidden: 1     →  skip
should_skip() {
    local fp hid
    fp=$(get_fm_value "$1" "frontpage")
    [[ "$fp" == "0" ]] && return 0
    hid=$(get_fm_value "$1" "hidden")
    [[ "$hid" == "1" ]]
}

# ── Docsify link ──────────────────────────────────────────────────────────────
# dir_link DIR_PATH  →  "/repo-relative/path/"
dir_link() {
    local rel="${1#$REPO_ROOT}"
    rel="${rel#/}"; rel="${rel%/}"
    [[ -z "$rel" ]] && rel="/" || rel="/$rel/"
    printf '%s' "$(printf '%s' "$rel" | sed -E 's:/{2,}:/:g')"
}

# ── Tag replacement ───────────────────────────────────────────────────────────
# replace_between_tags FILE TAG_NAME NEW_CONTENT
#
# Replaces the content between:
#   <!-- start-replace-TAG_NAME [attrs] -->
#   <!-- end-replace-TAG_NAME -->
# preserving both tag lines.  Safe to call repeatedly (idempotent).
replace_between_tags() {
    local file="$1" tag_name="$2" new_content="$3"
    local start_line end_line

    start_line=$(grep -n "<!-- start-replace-${tag_name}" "$file" | cut -d: -f1 | head -1)
    end_line=$(  grep -n "<!-- end-replace-${tag_name} -->"        "$file" | cut -d: -f1 | head -1)

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

    echo "  Updated: ${file#${REPO_ROOT}/}"
}
