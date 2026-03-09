# docsh

Français / French
------------------

`docsh` est une petite collection de scripts Bash pour faciliter la génération et la maintenance
de la documentation statique (par exemple pour Docsify). Les scripts parcourent l'arborescence
du projet, génèrent un `_sidebar.md`, insèrent des sous-navigations dans les `README.md` et
gèrent l'insertion d'éléments médias et de listes de fichiers.

Les scripts sont numérotés et s'exécutent dans cet ordre via `autorun.sh`.

### Scripts

**`30_generate_media.sh`**
Remplace le bloc entre `<!-- start-replace-media ... -->` et `<!-- end-replace-media -->` par
une liste d'images issues du dossier `medias/` du répertoire courant.
Option `no-caption` : utilise un espace comme texte alternatif (pas de légende).

```markdown
<!-- start-replace-media -->
* ![Mon Image](./medias/mon-image.jpg)
<!-- end-replace-media -->
```

---

**`35_generate_filelist.sh`**
Remplace le bloc entre `<!-- start-replace-filelist ... -->` et `<!-- end-replace-filelist -->`
par une liste de liens Markdown.

Comportement par défaut (sans arguments) : liste tout le contenu non-caché du dossier du
`README.md` (fichiers **et** sous-dossiers), en excluant `README.md` lui-même. Les titres
des sous-dossiers sont lus depuis leur propre `README.md`. Cela crée une navigation augmentée
et un inventaire de fichiers en un seul bloc.

Paramètres du tag :
- `folder="./chemin"` — dossier à scanner (défaut : dossier du `README.md`)
- `pattern="regex"` — filtre les noms de fichiers par expression régulière (défaut : tout)
- `recursive` *(flag)* — inclut les sous-dossiers
- `raw` *(flag)* — noms bruts sans mise en forme Title Case

```markdown
<!-- start-replace-filelist -->
- [Module 2020 Box Corner](./modules/2020-box-corner/)
- [Schema.pdf](./doc/schema.pdf)
<!-- end-replace-filelist -->

<!-- start-replace-filelist folder="./export" pattern="\.stl$" -->
- [Boite Extrusion EnsembleBody Bottom](./export/boite-extrusion-ensembleBody-bottom.stl)
<!-- end-replace-filelist -->
```

---

**`40_variable_expansion.sh`**
Remplace les variables inline ou blocs entre `<!-- %: CLE -->` et `<!-- %; -->` par leur valeur
définie dans un fichier `.variable_expansion` à la racine du dépôt.

Options CLI : `-f VARFILE`, `-r ROOT`, `-n` (dry-run), `-v` (verbose).

```markdown
Version : <!-- %: VERSION -->1.0<!-- %; -->
```

---

**`60_generate_subnav.sh`**
Insère ou met à jour une sous-navigation (liste de liens vers les sous-dossiers) entre les tags
`<!-- start-replace-subnav -->` et `<!-- end-replace-subnav -->` dans chaque `README.md`.
Supporte une image de couverture `_cover.png` / `_cover.jpg` dans les sous-dossiers.
Option `depth=N` dans le tag de début pour limiter la profondeur de récursion.

```markdown
<!-- start-replace-subnav depth=1 -->
* [Sous-section](./sous-section/)
<!-- end-replace-subnav -->
```

---

**`70_generate_sidebar.sh`**
Génère le fichier `_sidebar.md` à la racine du dépôt en parcourant tous les `README.md`.
Un fichier `.docshignore` dans un dossier exclut ce dossier et ses enfants.

Options CLI :
- `-r`, `--include-root` — inclut le `README.md` racine comme entrée de premier niveau
- `-h`, `--help` — aide

---

**`autorun.sh`**
Exécute tous les scripts `.sh` du dossier `docsh` dans l'ordre alphabétique/numérique,
sauf lui-même.

---

### Usage rapide

Exécuter tous les scripts depuis la racine du dépôt :

```bash
bash docsh/autorun.sh
```

Exécuter un script individuellement :

```bash
bash docsh/70_generate_sidebar.sh --include-root
```

### Bonnes pratiques

- Exécuter depuis la racine du dépôt pour que les chemins relatifs fonctionnent.
- Rendre les scripts exécutables si besoin : `chmod +x docsh/*.sh`.
- Utiliser `.docshignore` pour exclure un dossier de la sidebar et de la subnav.

English / Anglais
------------------

`docsh` is a small collection of Bash scripts to help generate and maintain static
documentation (for example, Docsify). Scripts are numbered and run in order via `autorun.sh`.

### Scripts

**`30_generate_media.sh`**
Replaces the block between `<!-- start-replace-media ... -->` and `<!-- end-replace-media -->`
with a list of images found in the directory's `medias/` folder.
`no-caption` flag: uses a space as alt text (no visible caption).

```markdown
<!-- start-replace-media -->
* ![My Image](./medias/my-image.jpg)
<!-- end-replace-media -->
```

---

**`35_generate_filelist.sh`**
Replaces the block between `<!-- start-replace-filelist ... -->` and `<!-- end-replace-filelist -->`
with a Markdown link list.

Default behaviour (no arguments): lists all non-hidden contents of the README's own directory
(files **and** subdirectories), excluding `README.md` itself. Subdirectory titles are read from
their own `README.md`. This produces an augmented navigation + file inventory in one block.

Tag parameters:
- `folder="./path"` — folder to scan (default: directory of the `README.md`)
- `pattern="regex"` — filter filenames by regex (default: list everything)
- `recursive` *(flag)* — include subdirectories
- `raw` *(flag)* — use bare filenames instead of Title Case link text

```markdown
<!-- start-replace-filelist -->
- [Module 2020 Box Corner](./modules/2020-box-corner/)
- [Schema.pdf](./doc/schema.pdf)
<!-- end-replace-filelist -->

<!-- start-replace-filelist folder="./export" pattern="\.stl$" -->
- [Boite Extrusion EnsembleBody Bottom](./export/boite-extrusion-ensembleBody-bottom.stl)
<!-- end-replace-filelist -->
```

---

**`40_variable_expansion.sh`**
Replaces inline or block variables between `<!-- %: KEY -->` and `<!-- %; -->` with values
defined in a `.variable_expansion` file at the repository root.

CLI options: `-f VARFILE`, `-r ROOT`, `-n` (dry-run), `-v` (verbose).

```markdown
Version: <!-- %: VERSION -->1.0<!-- %; -->
```

---

**`60_generate_subnav.sh`**
Inserts or updates a sub-navigation (links to subdirectories) between
`<!-- start-replace-subnav -->` and `<!-- end-replace-subnav -->` in each `README.md`.
Supports a `_cover.png` / `_cover.jpg` cover image in subdirectories.
Add `depth=N` in the start tag to limit recursion depth.

```markdown
<!-- start-replace-subnav depth=1 -->
* [Sub-section](./sub-section/)
<!-- end-replace-subnav -->
```

---

**`70_generate_sidebar.sh`**
Generates `_sidebar.md` at the repository root by walking all `README.md` files.
A `.docshignore` file in a directory excludes that directory and its children.

CLI options:
- `-r`, `--include-root` — include the root `README.md` as the top-level entry
- `-h`, `--help` — show help

---

**`autorun.sh`**
Runs all `.sh` scripts in the `docsh` folder in alphabetical/numeric order, skipping itself.

---

### Quick start

Run all scripts from the repository root:

```bash
bash docsh/autorun.sh
```

Run a single script:

```bash
bash docsh/70_generate_sidebar.sh --include-root
```

### Notes

- Run from the repository root so relative paths behave as expected.
- Make scripts executable if preferred: `chmod +x docsh/*.sh`.
- Use `.docshignore` to exclude a directory from the sidebar and subnav.

License
-------
See the `LICENSE` file in the repository.
