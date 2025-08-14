#!/bin/bash

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ HEIC to Image Converter (Cross-platform, ImageMagick v7+)┃
# ┃ Converts .heic to .jpg/.png/.webp/... with options        ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

print_help() {
  cat << EOF
Usage:
  $(basename "$0") [DIRECTORY] [options]

Convert all .heic images in a folder (recursively) to other formats
using ImageMagick. Output images are saved in the same folder.

Options:
  DIRECTORY            Folder to scan. Defaults to current directory.
  --maxdim N           Resize longest side of image to N pixels.
  --format EXT1,EXT2   Output formats (comma-separated). Default: jpg
  --bgcolor COLOR      Background color for alpha flattening (default: white)
  --strip              Strip metadata (default: preserve)
  --delete             Delete .heic after successful conversion
  --overwrite          Overwrite existing output files
  --skip-existing      Skip existing output files (default behavior)
  --help               Show this help message

Aliases:
  --max-long-side      Alias for --maxdim

Examples:
  ./convert_heic.sh
  ./convert_heic.sh ./img --maxdim 1920 --format jpg,png --bgcolor white
  ./convert_heic.sh ./img --format webp --strip --overwrite --delete

EOF
}

# ─────────────────────────────────────────────────────
# Defaults
TARGET_DIR="."
MAXDIM=""
FORMATS=("jpg")
STRIP_METADATA=false
DELETE_ORIGINAL=false
OVERWRITE=false
BGCOLOR="white"

# ─────────────────────────────────────────────────────
# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      print_help
      exit 0
      ;;
    --maxdim|--max-long-side)
      shift
      MAXDIM="$1"
      ;;
    --format)
      shift
      IFS=',' read -ra FORMATS <<< "$1"
      ;;
    --strip)
      STRIP_METADATA=true
      ;;
    --delete)
      DELETE_ORIGINAL=true
      ;;
    --overwrite)
      OVERWRITE=true
      ;;
    --skip-existing)
      OVERWRITE=false
      ;;
    --bgcolor)
      shift
      BGCOLOR="$1"
      ;;
    *)
      TARGET_DIR="$1"
      ;;
  esac
  shift
done

# ─────────────────────────────────────────────────────
# Check for magick
if ! command -v magick &>/dev/null; then
  echo "❌ Error: 'magick' not found. Please install ImageMagick v7+."
  exit 1
fi

# ─────────────────────────────────────────────────────
# Summary
echo "📁 Directory: $TARGET_DIR"
[ -n "$MAXDIM" ] && echo "📏 Max dimension: ${MAXDIM}px"
echo "🎨 Formats: ${FORMATS[*]}"
echo "🗂 Metadata: $([[ "$STRIP_METADATA" == true ]] && echo "stripped" || echo "preserved")"
echo "🎨 Background: $BGCOLOR"
echo "🗑 Delete original: $([[ "$DELETE_ORIGINAL" == true ]] && echo "yes" || echo "no")"
echo "♻️ Overwrite: $([[ "$OVERWRITE" == true ]] && echo "yes" || echo "no (skip existing)")"

# ─────────────────────────────────────────────────────
# Conversion loop
find "$TARGET_DIR" -type f -iname "*.heic" | while read -r heic_file; do
  base_name="${heic_file%.*}"

  for ext in "${FORMATS[@]}"; do
    out_file="${base_name}.${ext}"

    if [ -f "$out_file" ] && [ "$OVERWRITE" = false ]; then
      echo "⚠️  Skipping: $out_file already exists"
      continue
    fi

    echo "🔄 Converting: $(basename "$heic_file") → $(basename "$out_file")"

    # Metadata
    if [ "$STRIP_METADATA" = true ]; then
      META_ARGS="-strip"
    else
      META_ARGS="+profile '*'"
    fi

    # Alpha handling for formats that don't support transparency
    case "$ext" in
      jpg|jpeg)
        ALPHA_ARGS="-background $BGCOLOR -alpha remove -alpha off"
        ;;
      *)
        ALPHA_ARGS=""
        ;;
    esac

    # Resize if needed
    if [ -n "$MAXDIM" ]; then
      magick "$heic_file" -resize "${MAXDIM}x${MAXDIM}>" $ALPHA_ARGS $META_ARGS "$out_file"
    else
      magick "$heic_file" $ALPHA_ARGS $META_ARGS "$out_file"
    fi

    # Delete original HEIC if requested
    if [ "$DELETE_ORIGINAL" = true ]; then
      echo "🗑️  Deleting source: $heic_file"
      rm -f "$heic_file"
    fi
  done
done

echo "✅ All HEIC files processed."
