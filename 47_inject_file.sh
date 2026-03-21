#!/usr/bin/env bash
# docsh/47_inject_file.sh — Inject raw file content between HTML comment tags.
#
# Scans all *.md files under ROOT_DIR for <!-- start-inject-file ... --> /
# <!-- end-inject-file --> marker pairs and replaces the content between them
# with the verbatim content of the referenced file.
#
# This is the canonical way to embed a standalone file (e.g. an SVG interactive
# map) into a Markdown document while keeping a single source of truth: the SVG
# (or other file) lives in the repo and is re-injected on every docsh run.
#
# ── Tag syntax ───────────────────────────────────────────────────────────────
#
#   <!-- start-inject-file path="./interactive_map.svg" -->
#   <!-- end-inject-file -->
#
# ── Options (inside the opening tag) ─────────────────────────────────────────
#
#   path="REL_PATH"        Path to the file to inject, relative to the README
#                          that contains the tag.  Required.
#
#   base-url="https://…"   When set, any href="./…" or src="./…" attributes
#                          inside the injected content that start with "./" or
#                          "../" are rewritten to absolute URLs rooted at this
#                          base.  Useful so that images inside an inlined SVG
#                          resolve correctly when the page is embedded remotely.
#
#   wrap="OPEN|CLOSE"      Wrap the injected block with literal HTML strings.
#                          The pipe | separates the opening wrapper from the
#                          closing wrapper.  Default: no wrapper.
#                          Example:
#                            wrap='<div style="aspect-ratio:16/9">|</div>'
#
# ── Example (README.md) ──────────────────────────────────────────────────────
#
#   <!-- start-inject-file path="./interactive_map.svg"
#        base-url="https://sr-expo.gitlab.io/venues/2026/wam/"
#        wrap='<div style="width:100%;aspect-ratio:16/9;overflow:hidden;">|</div>' -->
#   <!-- end-inject-file -->
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash docsh/50_inject_file.sh [ROOT_DIR]
#     ROOT_DIR  root of the tree to scan (default: parent of the docsh/ folder)
#
#   Called automatically by docsh/autorun.sh.
#
# Requires: python3 (for path rewriting)

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Directory basenames excluded from scanning
EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh" "tools")

START_TAG_RE='<!--[[:space:]]*start-inject-file'
END_TAG_RE='<!--[[:space:]]*end-inject-file[[:space:]]*-->'

# ---------------------------------------------------------------------------
# Extract a named attribute value from an HTML comment opening tag string.
# Usage: extract_attr "path" "<!-- start-inject-file path=\"./foo.svg\" -->"
# ---------------------------------------------------------------------------
extract_attr() {
    local attr="$1"
    local tag_line="$2"
    # Match  attr="value"  or  attr='value'
    if [[ "$tag_line" =~ ${attr}=\"([^\"]*)\" ]]; then
        printf "%s" "${BASH_REMATCH[1]}"
    elif [[ "$tag_line" =~ ${attr}=\'([^\']*)\' ]]; then
        printf "%s" "${BASH_REMATCH[1]}"
    fi
}

# ---------------------------------------------------------------------------
# rewrite_relative_urls CONTENT_FILE BASE_URL
# Print CONTENT_FILE to stdout with relative href/src rewritten to absolute.
# python3 reads its script from the heredoc on stdin; CONTENT_FILE and
# BASE_URL are passed as positional arguments — no conflicting stdin sources.
# ---------------------------------------------------------------------------
rewrite_relative_urls() {
    local content_file="$1"
    local base_url="$2"

    if ! command -v python3 >/dev/null 2>&1; then
        cat -- "$content_file"
        return
    fi

    python3 - "$base_url" "$content_file" <<'PYEOF'
import sys, re, urllib.parse

base_url = sys.argv[1].rstrip("/") + "/"
text     = open(sys.argv[2]).read()

# Match  href="./..."  href='../...'  src="./..."  src='../...'
pattern = re.compile(r'''((?:href|src)=)(["'])((?:\.{1,2}/)[^"'\s>]*)(\2)''')

def replace(m):
    attr_eq, q, url, q2 = m.group(1), m.group(2), m.group(3), m.group(4)
    absolute = urllib.parse.urljoin(base_url, url)
    return f"{attr_eq}{q}{absolute}{q2}"

sys.stdout.write(pattern.sub(replace, text))
PYEOF
}

# ---------------------------------------------------------------------------
# Process a single README file: replace every inject-file block found in it.
# ---------------------------------------------------------------------------
process_readme() {
    local readme_path="$1"
    local readme_dir
    readme_dir="$(dirname "$readme_path")"

    # Quick skip if the file has no start tags at all
    if ! grep -qE "$START_TAG_RE" "$readme_path"; then
        return
    fi

    local tmp_path
    tmp_path="$(mktemp)"

    local in_block=0
    local replaced_any=0
    local tag_full=""

    # The file is redirected into the while loop so that inner `read` calls
    # (used to consume continuation lines of a multi-line tag) draw from the
    # same file descriptor as the outer loop.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $in_block -eq 0 ]]; then
            # ── Detect start of an inject block ──────────────────────────
            if [[ "$line" =~ $START_TAG_RE ]]; then
                # Collect the full opening tag — it may span multiple lines
                tag_full="$line"
                printf "%s\n" "$line" >> "$tmp_path"

                while [[ ! "$tag_full" =~ '-->' ]]; do
                    if ! IFS= read -r cont; then
                        echo "Warning: unterminated start-inject-file tag in $readme_path" >&2
                        break
                    fi
                    printf "%s\n" "$cont" >> "$tmp_path"
                    tag_full="$tag_full $cont"
                done

                # ── Parse attributes ──────────────────────────────────
                local inject_path base_url wrap_str
                inject_path="$(extract_attr "path" "$tag_full")"
                base_url="$(extract_attr "base-url" "$tag_full")"
                wrap_str="$(extract_attr "wrap" "$tag_full")"

                if [[ -z "$inject_path" ]]; then
                    echo "Warning: start-inject-file tag in $readme_path has no path= attribute. Skipping." >&2
                    in_block=1
                    continue
                fi

                local inject_file="$readme_dir/$inject_path"
                if [[ ! -f "$inject_file" ]]; then
                    echo "Warning: inject file not found: $inject_file (referenced from $readme_path)" >&2
                    in_block=1
                    continue
                fi

                # ── Emit wrapper open ─────────────────────────────────
                if [[ -n "$wrap_str" ]]; then
                    printf "%s\n" "${wrap_str%%|*}" >> "$tmp_path"
                fi

                # ── Emit (optionally rewritten) file content ─────────────
                if [[ -n "$base_url" ]]; then
                    rewrite_relative_urls "$inject_file" "$base_url" >> "$tmp_path"
                else
                    cat -- "$inject_file" >> "$tmp_path"
                fi
                # Ensure injected content ends with a newline
                printf "\n" >> "$tmp_path"

                # ── Emit wrapper close ────────────────────────────────────
                if [[ -n "$wrap_str" ]]; then
                    printf "%s\n" "${wrap_str#*|}" >> "$tmp_path"
                fi

                replaced_any=1
                in_block=1
            else
                printf "%s\n" "$line" >> "$tmp_path"
            fi

        else
            # ── Inside a block: discard lines until end tag ───────────────
            if [[ "$line" =~ $END_TAG_RE ]]; then
                printf "%s\n" "$line" >> "$tmp_path"
                in_block=0
                tag_full=""
            fi
            # Lines between the tags are silently dropped — replaced above
        fi

    done < "$readme_path"

    if [[ $replaced_any -eq 1 ]]; then
        mv -- "$tmp_path" "$readme_path"
        echo "  injected: $readme_path"
    else
        command rm -f -- "$tmp_path"
    fi
}

# ---------------------------------------------------------------------------
# Walk the tree, skipping excluded directories
# ---------------------------------------------------------------------------
found=0
while IFS= read -r -d '' readme; do
    skip=0
    for ex in "${EXCLUDED_DIRS[@]}"; do
        [[ "$readme" == *"/$ex/"* || "$readme" == *"/$ex" ]] && { skip=1; break; }
    done
    [[ $skip -eq 1 ]] && continue

    process_readme "$readme"
    (( found++ )) || true
done < <(find "$ROOT_DIR" -type f -name "*.md" -print0)

echo "50_inject_file: scanned $found Markdown file(s)."
