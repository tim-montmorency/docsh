done
#!/bin/bash

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

# Use the scripts directory as the root for running the contained scripts
ROOT_DIR="$SCRIPTS_DIR"

echo "Scripts directory: $SCRIPTS_DIR"
echo "Root directory: $ROOT_DIR"

# Do not attempt to install packages automatically in general-use script;
# just warn the user if bash is missing.
if ! command -v bash >/dev/null 2>&1; then
    echo "ERROR: Bash not found in PATH. Please install bash and re-run."
    exit 1
fi

# Change to the scripts directory so relative paths inside scripts behave as intended
cd "$ROOT_DIR" || { echo "Error: Could not change to scripts directory"; exit 1; }

echo "Running all scripts from docsh directory..."

# Count scripts for debugging
script_count=0
echo "Looking for scripts in: $SCRIPTS_DIR"
ls -la "$SCRIPTS_DIR"

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

        # Execute the script with bash
        if ! bash "$script"; then
            echo "Error: $script_name failed to execute." >&2
            exit 1
        fi
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
