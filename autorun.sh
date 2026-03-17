#!/bin/bash
# docsh/autorun.sh — Run all docsh generation scripts in sequence.
#
# Discovers and executes every *.sh file in the docsh/ folder (sorted by name),
# skipping autorun.sh itself.  Scripts always run from the repository root so
# that relative paths inside each script resolve correctly.
#
# Execution time is printed after each script.  Any script that exits non-zero
# aborts the run immediately.
#
# Usage:
#   bash docsh/autorun.sh
#   ./docsh/autorun.sh     (if the executable bit is set)

# Fail on error, undef vars, and fail pipelines; make globs return empty when no match
set -euo pipefail
shopt -s nullglob

# Resolve the script directory even when called via a symlink
SOURCE="${BASH_SOURCE[0]:-$0}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPTS_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

echo "Scripts directory: $SCRIPTS_DIR"

# Change to repo root so scripts that default to pwd() resolve correctly
cd "$SCRIPTS_DIR/.." || { echo "Error: Could not change to repo root"; exit 1; }

echo "Running all scripts from docsh directory..."

# Count scripts
script_count=0

# Execute all .sh scripts in the scripts dir except this one
for script in "$SCRIPTS_DIR"/*.sh; do
    # Only check if it's a file
    if [ -f "$script" ]; then
        # Get the script name without path
        script_name=$(basename "$script")

        # Skip autorun.sh (this script)
        if [ "$script_name" = "autorun.sh" ]; then
            echo "Skipping self ($script_name)..."
            continue
        fi

        echo "Running $script_name..."
        script_count=$((script_count + 1))
        t0=$SECONDS

        # Execute the script with bash
        if ! bash "$script"; then
            echo "Error: $script_name failed to execute." >&2
            exit 1
        fi
        echo "  done in $((SECONDS - t0))s"
    else
        echo "Skipping $script (not a file)"
    fi
done

if [ $script_count -eq 0 ]; then
    echo "WARNING: No scripts were found to execute in $SCRIPTS_DIR"
    echo "Make sure there are .sh files in the docsh directory."
else
    echo "Successfully executed $script_count script(s)."
fi
