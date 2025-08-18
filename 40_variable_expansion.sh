#!/bin/sh

# POSIX-compliant variable expansion for Markdown files.
# Reads a variables file where each non-empty, non-comment line is:
#   KEY <whitespace> VALUE...
# Replaces content between markers in markdown files:
#   <!-- varexp:begin KEY --> ... <!-- varexp:end -->

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
VERBOSE=0

# Space-separated excluded dirs
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

if [ ! -f "$VAR_FILE" ]; then
	# Resolve script directory and try a few sensible fallbacks. This makes the
	# script work when executed from inside docsh/ (autorun) while the
	# .variable_expansion file lives in the repository root.
	SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

	if [ -f "../$VAR_FILE" ]; then
		VAR_FILE="../$VAR_FILE"
		[ "$VERBOSE" = "1" ] && printf "Using parent-dir variable file: %s\n" "$VAR_FILE"
	elif [ -f "$SCRIPT_DIR/../$VAR_FILE" ]; then
		VAR_FILE="$SCRIPT_DIR/../$VAR_FILE"
		[ "$VERBOSE" = "1" ] && printf "Using script-parent variable file: %s\n" "$VAR_FILE"
	elif [ -f "$SCRIPT_DIR/$VAR_FILE" ]; then
		VAR_FILE="$SCRIPT_DIR/$VAR_FILE"
		[ "$VERBOSE" = "1" ] && printf "Using script-dir variable file: %s\n" "$VAR_FILE"
	else
		echo "Variable file not found: $VAR_FILE (tried parent dir and script paths). Pass -f to specify." >&2
		exit 2
	fi
fi

if [ "$VERBOSE" = "1" ]; then
	echo "Using variable file: $VAR_FILE"
	echo "Root dir: $ROOT_DIR"
	echo "Excluded dirs: $EXCLUDED_DIRS"
fi

# Build find prune expression string (quoted parts kept literal)
PRUNE_EXPR=""
for d in $EXCLUDED_DIRS; do
	PRUNE_EXPR="$PRUNE_EXPR -path '$ROOT_DIR/$d' -prune -o"
done

FIND_CMD="find '$ROOT_DIR' $PRUNE_EXPR -type f -name '*.md' -print"
if [ "$VERBOSE" = "1" ]; then
	echo "Find command: $FIND_CMD"
fi

MD_FOUND=0
eval "$FIND_CMD" | while IFS= read -r file; do
	MD_FOUND=1
	# Resolve absolute path of the file to allow reliable comparisons against script dir
	file_dir=$(dirname "$file")
	file_base=$(basename "$file")
	abs_file_dir=$(cd "$file_dir" 2>/dev/null && pwd || echo "")
	abs_file="$abs_file_dir/$file_base"
	# Skip files that live under the script directory (example docs inside docsh/)
	if [ -n "${SCRIPT_DIR:-}" ]; then
		case "$abs_file" in
			"$SCRIPT_DIR"/*)
				[ "$VERBOSE" = "1" ] && printf "Skipping file inside script dir: %s\n" "$abs_file"
				continue
				;;
		esac
	fi
	# Skip the variable file itself if it's inside the tree
	if [ "$file" = "$VAR_FILE" ]; then
		continue
	fi

	if [ "$VERBOSE" = "1" ]; then
		printf "Processing: %s\n" "$file"
	fi

	if [ "$DRY_RUN" = "1" ]; then
		perl -0777 -e '
			my $varfile = shift @ARGV;
			open my $vh, "<", $varfile or die "Cannot open $varfile: $!";
			my %v;
			{ local $/ = "\n"; while(<$vh>){ chomp; next if /^\s*#/; next if /^\s*$/; my ($k,$rest)=split(/\s+/, $_, 2); $rest = "" unless defined $rest; $rest =~ s/\r//g; $rest =~ s/\n/ /g; $rest =~ s/^\s+|\s+$//g; $v{$k} = $rest } }
			local $/ = undef; my $file = shift @ARGV; open my $fh, "<", $file or die "open $file: $!"; my $t = <$fh>; close $fh;
			my $changed = 0;
					$t =~ s{(<!--\s*varexp:begin\s+([^\s>]+)\s*-->)(.*?)(<!--\s*varexp:end\s*-->)}{
						my ($open,$key,$old,$close) = ($1,$2,$3,$4);
						if (exists $v{$key}){ $changed = 1; $open . $v{$key} . $close }
						else { warn "Warning: key $key not defined (file: $file)\n"; $open . $old . $close }
					}ges;
			print STDOUT ($changed ? "CHANGED:$file\n" : "UNCHANGED:$file\n");
		' "$VAR_FILE" "$file"
	else
		tmpfile="${file}.tmp.$$"
		perl -0777 -e '
			my $varfile = shift @ARGV;
			open my $vh, "<", $varfile or die "Cannot open $varfile: $!";
			my %v;
			{ local $/ = "\n"; while(<$vh>){ chomp; next if /^\s*#/; next if /^\s*$/; my ($k,$rest)=split(/\s+/, $_, 2); $rest = "" unless defined $rest; $rest =~ s/\r//g; $rest =~ s/\n/ /g; $rest =~ s/^\s+|\s+$//g; $v{$k} = $rest } }
			local $/ = undef; my $file = shift @ARGV; open my $fh, "<", $file or die "open $file: $!"; my $t = <$fh>; close $fh;
					$t =~ s{(<!--\s*varexp:begin\s+([^\s>]+)\s*-->)(.*?)(<!--\s*varexp:end\s*-->)}{
						my ($open,$key,$old,$close) = ($1,$2,$3,$4);
						if (exists $v{$key}){ $open . $v{$key} . $close }
						else { warn "Warning: key $key not defined (file: $file)\n"; $open . $old . $close }
					}ges;
			print STDOUT $t;
		' "$VAR_FILE" "$file" > "$tmpfile"
		# Replace original file with tmp
		if [ -f "$tmpfile" ]; then
			mv "$tmpfile" "$file"
		fi
	fi
done

if [ "$MD_FOUND" = "0" ]; then
	if [ "$VERBOSE" = "1" ]; then
		printf "No markdown files found under %s\n" "$ROOT_DIR"
	fi
fi

exit 0
