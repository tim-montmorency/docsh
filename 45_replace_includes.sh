#!/bin/bash

EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode" "docsh")
ROOT_DIR=$(pwd)

START_INCLUDE_PATTERN='^[[:space:]]*<!--[[:space:]]*start-replace-include[[:space:]]+([^[:space:]]+)[[:space:]]*-->[[:space:]]*$'
END_INCLUDE_PATTERN='^[[:space:]]*<!--[[:space:]]*end-replace-include[[:space:]]*-->[[:space:]]*$'

should_exclude_path() {
    local path="$1"
    for excluded in "${EXCLUDED_DIRS[@]}"; do
        if [[ "$path" == *"/$excluded/"* ]]; then
            return 0
        fi
    done
    return 1
}

replace_include_blocks() {
    local readme_path="$1"
    local readme_dir
    readme_dir=$(dirname "$readme_path")

    local tmp_path
    tmp_path=$(mktemp)

    local in_include_block=0
    local replaced_any=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $in_include_block -eq 0 ]]; then
            if [[ "$line" =~ $START_INCLUDE_PATTERN ]]; then
                local include_path="${BASH_REMATCH[1]}"
                local include_file="$readme_dir/$include_path"

                echo "$line" >> "$tmp_path"

                if [[ -f "$include_file" ]]; then
                    local include_dir_abs
                    include_dir_abs="$(dirname "$include_file")"
                    local parent_dir_abs
                    parent_dir_abs="$readme_dir"

                    if command -v python3 >/dev/null 2>&1; then
                        python3 - "$include_dir_abs" "$parent_dir_abs" "$include_file" >> "$tmp_path" <<'PY'
import posixpath
import re
import sys

include_dir = sys.argv[1]
parent_dir = sys.argv[2]
include_file = sys.argv[3]

with open(include_file, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(
    r'(?m)^[ \t]*<!--[ \t]*start-replace-subnav(?:\s+[^>]*)?[ \t]*-->[ \t]*\n?',
    '',
    text,
)
text = re.sub(
    r'(?m)^[ \t]*<!--[ \t]*end-replace-subnav[ \t]*-->[ \t]*\n?',
    '',
    text,
)

pattern = re.compile(r'\]\(([^)\s]+)([^)]*)\)')

def rewrite(match):
    target = match.group(1)
    suffix = match.group(2)

    if target.startswith('./') or target.startswith('../'):
        keep_trailing = target.endswith('/')
        include_abs = posixpath.normpath(posixpath.join(include_dir, target))
        parent_abs = posixpath.normpath(parent_dir)
        rel = posixpath.relpath(include_abs, parent_abs)

        if rel == '.':
            rel = './'
        elif not rel.startswith('../'):
            rel = './' + rel

        if keep_trailing and rel != './' and not rel.endswith('/'):
            rel += '/'

        return '](' + rel + suffix + ')'

    return match.group(0)

text = pattern.sub(rewrite, text)

sys.stdout.write(text)
PY
                    else
                        cat "$include_file" >> "$tmp_path"
                    fi

                    printf "\n" >> "$tmp_path"
                    replaced_any=1
                else
                    echo "Warning: include file not found for $readme_path -> $include_path"
                fi

                in_include_block=1
            else
                echo "$line" >> "$tmp_path"
            fi
        else
            if [[ "$line" =~ $END_INCLUDE_PATTERN ]]; then
                echo "$line" >> "$tmp_path"
                in_include_block=0
            fi
        fi
    done < "$readme_path"

    mv "$tmp_path" "$readme_path"

    if [[ $replaced_any -eq 1 ]]; then
        echo "Updated include blocks in $readme_path"
    fi
}

while IFS= read -r -d '' readme_path; do
    if should_exclude_path "$readme_path"; then
        continue
    fi
    replace_include_blocks "$readme_path"
done < <(find "$ROOT_DIR" -type f -name "README.md" -print0)
