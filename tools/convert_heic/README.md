# Convert HEIC to other format

A portable and extensible Bash script to **batch convert `.heic` files** into standard image formats like **JPG, PNG, WebP**, and more using **ImageMagick**.

Supports macOS, Linux, and Windows (via Git Bash).


## ✅ Features

- 🔄 Convert `.heic` files to one or more image formats
- 📏 Resize longest side with `--maxdim`
- 🎯 Supports multiple output formats: `jpg`, `png`, `webp`, etc.
- 🗂 Metadata: preserved by default, or stripped with `--strip`
- 🧼 Optionally delete source `.heic` files after conversion
- ♻️ Choose to overwrite or skip existing output files
- 🖥️ Cross-platform compatible with **ImageMagick v7+**


## 🛠 Requirements

- [ImageMagick v7+](https://imagemagick.org) (`magick` command)
- ImageMagick must support **HEIC** format (`libheif`)

Check HEIC support with:
```bash
magick -list format | grep HEIC
````

## 🚀 Usage

```bash
./convert_heic.sh [DIRECTORY] [options]
```

### Arguments

| Option               | Description                                                  |
| -------------------- | ------------------------------------------------------------ |
| `DIRECTORY`          | Folder to scan (default: current directory)                  |
| `--maxdim N`         | Resize longest side to N pixels (preserve aspect)            |
| `--format EXT1,EXT2` | Comma-separated list of output formats (default: `jpg`)      |
| `--strip`            | Strip all metadata from output files                         |
| `--delete`           | Delete `.heic` file after successful conversion              |
| `--overwrite`        | Overwrite existing files without prompt                      |
| `--skip-existing`    | Skip conversion if output file exists (**default behavior**) |
| `--help`             | Show help message                                            |

### Aliases

* `--max-long-side` is an alias for `--maxdim`


## 🧪 Examples

Convert all `.heic` files in the current folder to `.jpg`:

```bash
./convert_heic.sh
```

Convert and resize to 1920px long side:

```bash
./convert_heic.sh ./photos --maxdim 1920
```

Convert to `.png` and `.webp`, strip metadata, delete original, and overwrite:

```bash
./convert_heic.sh ./images --format png,webp --strip --delete --overwrite
```


## 📦 Installation

No installation needed. Just make the script executable:

```bash
chmod +x convert_heic.sh
```

Then run from terminal.


## 📁 License

MIT License. Use freely in personal and commercial projects.


