#!/usr/bin/env bash
set -euo pipefail

# remove_empty_md.sh
# Recursively remove empty or whitespace-only Markdown files under a path.
# Usage: remove_empty_md.sh <path> [--dry-run|-n] [--verbose|-v]

progname=$(basename "$0")
dry_run=0
verbose=0

usage() {
	cat <<EOF
Usage: $progname PATH [--dry-run|-n] [--verbose|-v]

Recursively remove .md files that are empty or contain only whitespace under PATH.

Options:
	-n, --dry-run   Show files that would be removed but do not delete them
	-v, --verbose   Print each removed file
	-h, --help      Show this help
EOF
}

if [ "$#" -lt 1 ]; then
	usage
	exit 2
fi

path=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		-n|--dry-run)
			dry_run=1; shift ;;
		-v|--verbose)
			verbose=1; shift ;;
		-h|--help)
			usage; exit 0 ;;
		--)
			shift; break ;;
		-* )
			echo "Unknown option: $1" >&2; usage; exit 2 ;;
		*)
			path="$1"; shift ;;
	esac
done

if [ -z "$path" ]; then
	echo "Error: path is required" >&2
	usage
	exit 2
fi

if [ ! -d "$path" ]; then
	echo "Error: path not found or not a directory: $path" >&2
	exit 2
fi

# Find .md files and remove those that are empty or contain only whitespace.
# Use NUL delimiters to be safe with weird filenames.
removed=0
skipped=0

find "$path" -type f -iname '*.md' -print0 | while IFS= read -r -d '' file; do
	# If file contains any non-space character, keep it.
	if grep -q '[^[:space:]]' -- "$file"; then
		skipped=$((skipped+1))
		continue
	fi

	if [ "$dry_run" -eq 1 ]; then
		echo "DRY-RUN: would remove: $file"
	else
		if rm -f -- "$file"; then
			removed=$((removed+1))
			[ "$verbose" -eq 1 ] && echo "Removed: $file"
		else
			echo "Failed to remove: $file" >&2
		fi
	fi
done

if [ "$dry_run" -eq 1 ]; then
	echo "Dry run complete. No files were deleted."
else
	echo "Done. Removed $removed file(s)."
fi

exit 0

