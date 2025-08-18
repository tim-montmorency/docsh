#!/bin/sh
# POSIX Markdown variable expansion:
#   <!-- varexp:begin KEY -->...<!-- varexp:end -->
# Supports:
#   1) Inline:  "# TP1 <!-- varexp:begin K -->VAL<!-- varexp:end -->"
#   2) Block:   "# TP1\n<!-- varexp:begin K -->\nVAL\n<!-- varexp:end -->"
# Preserves original line ending style (LF/CRLF/CR).

set -eu

PROG_NAME=$(basename "$0")

usage() {
	cat <<EOF
Usage: $PROG_NAME [-f VARFILE] [-r ROOT] [-n] [-v]

Defaults:
  VARFILE=.variable_expansion
  ROOT=.

Options:
  -f VARFILE  variables file (default .variable_expansion)
  -r ROOT     root directory to scan (default .)
  -n          dry-run (don't modify files)
  -v          verbose
  -h          help
EOF
}

VAR_FILE=.variable_expansion
ROOT_DIR=.
DRY_RUN=0
VERBOSE=1

# Space-separated excluded dirs (relative to ROOT_DIR)
EXCLUDED_DIRS=".git node_modules __pycache__ .vscode docsh tools"

while getopts "f:r:nvh" opt; do
	case "$opt" in
		f) VAR_FILE=$OPTARG ;;
		r) ROOT_DIR=$OPTARG ;;
		n) DRY_RUN=1 ;;
		v) VERBOSE=1 ;;
		h) usage; exit 0 ;;
		*) echo "Invalid option" >&2; usage; exit 2 ;;
	esac
done

# Resolve script directory once
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Autorun: if invoked from inside the script dir and ROOT is ".", scan the parent
if [ "$ROOT_DIR" = "." ] && [ "$(pwd)" = "$SCRIPT_DIR" ]; then
	ROOT_DIR=$(dirname "$SCRIPT_DIR")
	[ "$VERBOSE" = "1" ] && printf "Autorun detected: adjusting root to %s\n" "$ROOT_DIR"
fi

# Find the variable file if not present where requested
if [ ! -f "$VAR_FILE" ]; then
	VAR_BASENAME=$(basename "$VAR_FILE")
	cur_dir=$(pwd)
	found=0
	while [ "$cur_dir" != "/" ]; do
		if [ -f "$cur_dir/$VAR_BASENAME" ]; then
			VAR_FILE="$cur_dir/$VAR_BASENAME"
			found=1
			[ "$VERBOSE" = "1" ] && printf "Found variable file while searching up: %s\n" "$VAR_FILE"
			break
		fi
		cur_dir=$(dirname "$cur_dir")
	done

	if [ "$found" -ne 1 ]; then
		if [ -f "$SCRIPT_DIR/../$VAR_BASENAME" ]; then
			VAR_FILE="$SCRIPT_DIR/../$VAR_BASENAME"
			[ "$VERBOSE" = "1" ] && printf "Using script-parent variable file: %s\n" "$VAR_FILE"
		elif [ -f "$SCRIPT_DIR/$VAR_BASENAME" ]; then
			VAR_FILE="$SCRIPT_DIR/$VAR_BASENAME"
			[ "$VERBOSE" = "1" ] && printf "Using script-dir variable file: %s\n" "$VAR_FILE"
		else
			echo "Variable file not found: $VAR_FILE (searched upward and script paths). Pass -f to specify." >&2
			exit 2
		fi
	fi
fi

# Absolute path to reliably compare later
ABS_VAR_FILE=$(cd "$(dirname "$VAR_FILE")" 2>/dev/null && pwd || echo "")/$(basename "$VAR_FILE")

# Basic env info
if [ "$VERBOSE" = "1" ]; then
	echo "Using variable file: $VAR_FILE"
	echo "Root dir: $ROOT_DIR"
	echo "Excluded dirs: $EXCLUDED_DIRS"
fi

# Check perl availability up front
if ! command -v perl >/dev/null 2>&1; then
	echo "perl not found in PATH (required)" >&2
	exit 2
fi

# Build a find(1) command string with prunes; evaluate it once into a temp list
PRUNE_EXPR=""
for d in $EXCLUDED_DIRS; do
	PRUNE_EXPR="$PRUNE_EXPR -path '$ROOT_DIR/$d' -prune -o"
done
FIND_CMD="find '$ROOT_DIR' $PRUNE_EXPR -type f -name '*.md' -print"

[ "$VERBOSE" = "1" ] && echo "Find command: $FIND_CMD"

LIST_FILE=".$PROG_NAME.$$".list
trap 'rm -f "$LIST_FILE" 2>/dev/null || true' EXIT INT HUP TERM
: > "$LIST_FILE"
# shellcheck disable=SC2086
eval "$FIND_CMD" > "$LIST_FILE"

if [ ! -s "$LIST_FILE" ]; then
	[ "$VERBOSE" = "1" ] && printf "No markdown files found under %s\n" "$ROOT_DIR"
	exit 0
fi

while IFS= read -r file; do
	file_dir=$(dirname "$file")
	file_base=$(basename "$file")
	abs_file_dir=$(cd "$file_dir" 2>/dev/null && pwd || echo "")
	abs_file="$abs_file_dir/$file_base"

	# Skip files under the script directory
	case "$abs_file" in
		"$SCRIPT_DIR"/*)
			[ "$VERBOSE" = "1" ] && printf "Skipping file inside script dir: %s\n" "$abs_file"
			continue
			;;
	esac

	# Skip the variable file itself
	if [ "$abs_file" = "$ABS_VAR_FILE" ]; then
		continue
	fi

	[ "$VERBOSE" = "1" ] && printf "Processing: %s\n" "$file"

	if [ "$DRY_RUN" = "1" ]; then
		perl -0777 -e '
			my $varfile = shift @ARGV;
			open my $vh, "<", $varfile or die "Cannot open $varfile: $!";
			my %v;
			{ local $/ = "\n";
			  while (<$vh>) {
				chomp;
				next if /^\s*#/ || /^\s*$/;
				my ($k,$rest)=split(/\s+/, $_, 2);
				$rest = "" unless defined $rest;
				$rest =~ s/\r//g;
				$rest =~ s/\n/ /g;
				$rest =~ s/^\s+|\s+$//g;
				$v{$k} = $rest;
			  }
			}
			local $/ = undef;
			my $file = shift @ARGV;
			open my $fh, "<", $file or die "open $file: $!";
			my $t = <$fh>;
			close $fh;

			# Detect newline style in the document
			my $nl = ($t =~ /\r\n/) ? "\r\n" : (($t =~ /\r(?!\n)/) ? "\r" : "\n");

			my $changed = 0;

			# Pass 1: BLOCK style (begin/end on their own lines). Preserve indentation & newline style.
			$t =~ s{
				^([ \t]*)
				(<!--\s*varexp:begin\s+([^\s>]+)\s*-->)
				[ \t]*\R
				(.*?)
				^\1
				(<!--\s*varexp:end\s*-->)
			}{
				my ($indent,$open,$key,$body,$close) = ($1,$2,$3,$4,$5);
				if (exists $v{$key}) {
					$changed = 1;
					$indent.$open.$nl.$v{$key}.$nl.$indent.$close
				} else {
					warn "Warning: key $key not defined (file: $file)\n";
					$indent.$open.$nl.$body.$nl.$indent.$close
				}
			}gemsx;

			# Pass 2: INLINE style (begin/end on the same line only).
			$t =~ s{
				(<!--\s*varexp:begin\s+([^\s>]+)\s*-->)
				([^\r\n]*?)
				(<!--\s*varexp:end\s*-->)
			}{
				my ($open,$key,$body,$close) = ($1,$2,$3,$4);
				if (exists $v{$key}) {
					$changed = 1;
					$open.$v{$key}.$close
				} else {
					warn "Warning: key $key not defined (file: $file)\n";
					$open.$body.$close
				}
			}gex;

			print STDOUT ($changed ? "UPDATED:$file\n" : "UNCHANGED:$file\n");
		' "$VAR_FILE" "$file"
	else
		tmpfile="${file}.tmp.$$"
		perl -0777 -e '
			my $varfile = shift @ARGV;
			open my $vh, "<", $varfile or die "Cannot open $varfile: $!";
			my %v;
			{ local $/ = "\n";
			  while (<$vh>) {
				chomp;
				next if /^\s*#/ || /^\s*$/;
				my ($k,$rest)=split(/\s+/, $_, 2);
				$rest = "" unless defined $rest;
				$rest =~ s/\r//g;
				$rest =~ s/\n/ /g;
				$rest =~ s/^\s+|\s+$//g;
				$v{$k} = $rest;
			  }
			}
			local $/ = undef;
			my $file = shift @ARGV;
			open my $fh, "<", $file or die "open $file: $!";
			my $t = <$fh>;
			close $fh;

			# Detect newline style in the document
			my $nl = ($t =~ /\r\n/) ? "\r\n" : (($t =~ /\r(?!\n)/) ? "\r" : "\n");

			# Pass 1: BLOCK style
			$t =~ s{
				^([ \t]*)
				(<!--\s*varexp:begin\s+([^\s>]+)\s*-->)
				[ \t]*\R
				(.*?)
				^\1
				(<!--\s*varexp:end\s*-->)
			}{
				my ($indent,$open,$key,$body,$close) = ($1,$2,$3,$4,$5);
				if (exists $v{$key}) {
					$indent.$open.$nl.$v{$key}.$nl.$indent.$close
				} else {
					warn "Warning: key $key not defined (file: $file)\n";
					$indent.$open.$nl.$body.$nl.$indent.$close
				}
			}gemsx;

			# Pass 2: INLINE style (same line)
			$t =~ s{
				(<!--\s*varexp:begin\s+([^\s>]+)\s*-->)
				([^\r\n]*?)
				(<!--\s*varexp:end\s*-->)
			}{
				my ($open,$key,$body,$close) = ($1,$2,$3,$4);
				if (exists $v{$key}) {
					$open.$v{$key}.$close
				} else {
					warn "Warning: key $key not defined (file: $file)\n";
					$open.$body.$close
				}
			}gex;

			print STDOUT $t;
		' "$VAR_FILE" "$file" > "$tmpfile"

		if [ -f "$tmpfile" ]; then
			if cmp -s "$file" "$tmpfile" 2>/dev/null; then
				rm -f "$tmpfile"
				[ "$VERBOSE" = "1" ] && printf "UNCHANGED:%s\n" "$file"
			else
				mv "$tmpfile" "$file"
				[ "$VERBOSE" = "1" ] && printf "UPDATED:%s\n" "$file"
			fi
		fi
	fi
done < "$LIST_FILE"

exit 0
