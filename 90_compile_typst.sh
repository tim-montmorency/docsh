#!/bin/bash
# 90_compile_typst.sh — Compile all Typst entry-point documents found under ROOT_DIR.
#
# ── Convention (mirrors Sass / Jekyll / Hugo) ────────────────────────────────
#   _*.typ   partial / shared include — SKIPPED, never compiled directly
#   *.typ    entry point              — compiled to <same-stem>.pdf
#
# ── Output naming ────────────────────────────────────────────────────────────
#   The PDF takes the exact same stem as the .typ file, placed alongside it.
#   Name the entry point what you want the PDF to be called, e.g.:
#
#     cv/guillaume_arseneault_cv.typ  →  cv/guillaume_arseneault_cv.pdf
#
# ── Root resolution ──────────────────────────────────────────────────────────
#   typst compile needs --root to resolve cross-directory imports such as:
#     #import "../_shared.typ": ...
#
#   For each .typ file the root is detected by walking up from its directory:
#     1. Directory containing a .typst-root marker file  (explicit override)
#     2. Directory containing a .git folder              (standard project root)
#     3. The .typ file's own directory                   (safe fallback)
#
#   To use a custom root in any sub-project, drop an empty .typst-root file:
#     touch my-subproject/.typst-root
#
# ── Auto-install ─────────────────────────────────────────────────────────────
#   If typst is not on PATH the script downloads the official pre-built binary
#   from GitHub Releases and installs it to ~/.local/bin (no sudo, no package
#   manager).  Supported platforms:
#
#     macOS   arm64 / x86_64
#     Linux   x86_64 / aarch64 (static musl binary, works on any distro)
#
#   The install runs once; subsequent runs just use the cached binary.
#   To force a reinstall: rm ~/.local/bin/typst
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash docsh/90_compile_typst.sh [DIR]
#     DIR  root of the tree to search (default: parent of the docsh/ folder)
#
#   Called automatically by docsh/autorun.sh when present in the docsh/ folder.

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# ---------------------------------------------------------------------------
# find_typst_root <dir>
#   Walk up from <dir> to find the nearest .typst-root marker or .git dir.
#   Prints the resolved root path.
# ---------------------------------------------------------------------------
find_typst_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.typst-root" || -d "$dir/.git" ]]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    # Fallback: compile relative to the file's own directory
    echo "$1"
}

# ---------------------------------------------------------------------------
# install_typst
#   Download the official pre-built typst binary for the current OS/arch and
#   install it to TYPST_INSTALL_DIR (~/.local/bin by default).
#   Uses curl (preferred) or wget as a fallback.
# ---------------------------------------------------------------------------
TYPST_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local}/bin"

install_typst() {
    local os arch asset_name download_url tmpdir

    # ── Detect OS and architecture ──────────────────────────────────────
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin)
            case "$arch" in
                arm64)  asset_name="typst-aarch64-apple-darwin" ;;
                x86_64) asset_name="typst-x86_64-apple-darwin"  ;;
                *) echo "Typst auto-install: unsupported macOS arch '$arch'." >&2; return 1 ;;
            esac
            ;;
        Linux)
            case "$arch" in
                x86_64)          asset_name="typst-x86_64-unknown-linux-musl"   ;;
                aarch64|arm64)   asset_name="typst-aarch64-unknown-linux-musl"  ;;
                *) echo "Typst auto-install: unsupported Linux arch '$arch'." >&2; return 1 ;;
            esac
            ;;
        *)
            echo "Typst auto-install: unsupported OS '$os'." >&2
            echo "  Please install typst manually: https://typst.app"
            return 1
            ;;
    esac

    download_url="https://github.com/typst/typst/releases/latest/download/${asset_name}.tar.xz"

    echo "Typst not found — installing to ${TYPST_INSTALL_DIR}/typst"
    echo "  Source: $download_url"

    # ── Download and extract ────────────────────────────────────────────
    tmpdir="$(mktemp -d)"
    local archive="${tmpdir}/${asset_name}.tar.xz"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --progress-bar "$download_url" -o "$archive"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$download_url" -O "$archive"
    else
        echo "Typst auto-install: neither curl nor wget found." >&2
        rm -rf "$tmpdir"
        return 1
    fi

    # The release tarball extracts to a directory named after the asset.
    # The typst binary lives at: <asset_name>/typst
    tar -xJf "$archive" -C "$tmpdir"
    mkdir -p "$TYPST_INSTALL_DIR"
    mv "${tmpdir}/${asset_name}/typst" "${TYPST_INSTALL_DIR}/typst"
    chmod +x "${TYPST_INSTALL_DIR}/typst"
    rm -rf "$tmpdir"

    echo "  Installed: $( "${TYPST_INSTALL_DIR}/typst" --version )"
}

# ---------------------------------------------------------------------------
# Resolve typst binary — install automatically on first use if missing.
# ---------------------------------------------------------------------------
TYPST_BIN="$(command -v typst 2>/dev/null || echo "")"

if [[ -z "$TYPST_BIN" ]]; then
    # Check the user install dir even if it's not yet on PATH
    if [[ -x "${TYPST_INSTALL_DIR}/typst" ]]; then
        TYPST_BIN="${TYPST_INSTALL_DIR}/typst"
    else
        install_typst || { echo "Error: could not install typst. Skipping compilation." >&2; exit 0; }
        TYPST_BIN="${TYPST_INSTALL_DIR}/typst"
    fi
fi

echo "Compiling Typst documents under: $ROOT_DIR"

compiled=0
errors=0

# Find all *.typ files; skip:
#   _*.typ          — partials / shared includes (underscore-prefix convention)
#   .git/**         — version control internals
#   node_modules/** — JS dependencies
#   .typst-cache/** — Typst's own compilation cache
while IFS= read -r typ_file; do
    filename="$(basename "$typ_file")"
    dir="$(dirname   "$typ_file")"
    stem="${filename%.typ}"
    pdf_out="${dir}/${stem}.pdf"
    typst_root="$(find_typst_root "$dir")"

    echo "  → ${typ_file#"${ROOT_DIR}/"}"
    if "$TYPST_BIN" compile --root "$typst_root" "$typ_file" "$pdf_out"; then
        compiled=$((compiled + 1))
    else
        echo "  ✗ compile failed: $typ_file" >&2
        errors=$((errors + 1))
    fi
done < <(find "$ROOT_DIR" \
    -name "*.typ" \
    ! -name "_*.typ" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.typst-cache/*" \
    | sort)

echo ""
if [[ $errors -eq 0 ]]; then
    echo "Typst: $compiled document(s) compiled."
else
    echo "Typst: $compiled compiled, $errors failed." >&2
fi

[[ $errors -eq 0 ]]
