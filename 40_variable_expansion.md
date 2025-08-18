## Variable expansion script

This document describes `40_variable_expansion.sh`.

Overview
- The script reads variable definitions from a file (default: `.variable_expansion`).
- Each non-empty, non-comment line must have the form: `KEY <whitespace> VALUE...`.
- It scans markdown files and replaces content between markers:
  `<!-- varexp:begin KEY --> ... <!-- varexp:end -->`
  with the VALUE for KEY, preserving the markers themselves.

Usage

From the repository root:

```bash
./docsh/40_variable_expansion.sh -f .variable_expansion --dry-run --verbose
```

Options
- `-f, --file`: variables file (default `.variable_expansion`).
- `-r, --root`: root directory to scan (default `.`).
- `--dry-run`: don't modify files; prints which files would change.
- `--verbose`: print progress messages.

Notes and behavior
- Lines starting with `#` or blank lines in the variable file are ignored.
- If a marker references an undefined key, a warning is printed and the inner content
  is left unchanged.
- The script performs atomic updates by writing to a temporary file and renaming it.
- Multi-line variable values are not supported by the default format. If you need
  multi-line values consider switching to a small YAML file and updating the script.

Examples

`.variable_expansion`:

```
hello this is a test
hello2 this is another test
```

`some.md` before:

```
Intro
<!-- varexp:begin hello -->
this is a test
hello2 this is another test
<!-- varexp:end -->
```

After running the script (non-dry run):

```
Intro
<!-- varexp:begin hello -->
this is a test
hello2 this is another test
<!-- varexp:end -->
```
