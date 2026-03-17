# docsh

Français / French
------------------

`docsh` est une petite collection de scripts Bash pour faciliter la génération et la maintenance
de la documentation statique (par exemple pour Docsify). Les scripts parcourent l'arborescence
du projet, génèrent un `_sidebar.md` et un `_navbar.md`, insèrent des sous-navigations dans les
`README.md`, récupèrent les listes de dépôts git depuis GitHub, GitLab et Codeberg, compilent
les documents Typst et gèrent l'insertion d'éléments médias et de listes de fichiers.

Les scripts sont numérotés et s'exécutent dans cet ordre via `autorun.sh`.

### Prérequis

- `bash` 4+, `python3`, `git`
- `typst` — seulement pour `90_compile_typst.sh`
- `GITHUB_TOKEN` (optionnel) — évite la limite de débit de l'API GitHub dans `80_generate_gitrepos.sh`

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

Comportement par défaut : liste tout le contenu non-caché du dossier du `README.md` (fichiers
**et** sous-dossiers), en excluant `README.md` lui-même.

Paramètres du tag :
- `folder="./chemin"` — dossier à scanner (défaut : dossier du `README.md`)
- `pattern="regex"` — filtre les noms de fichiers par expression régulière
- `recursive` *(flag)* — inclut les sous-dossiers
- `raw` *(flag)* — noms bruts sans mise en forme Title Case

```markdown
<!-- start-replace-filelist folder="./export" pattern="\.stl$" -->
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

**`50_generate_frontmatter_content.sh`**
Scanne les `README.md` pour leurs métadonnées YAML frontmatter et génère du contenu Markdown
formaté (grille d'images, liste ou tableau) entre les tags `<!-- start-replace-frontmatter -->`.

Paramètres du tag :
- `dir="./chemin"` — dossier à scanner
- `filter="cle=valeur"` — filtre par champ frontmatter (ex. `filter="frontpage=1"`)
- `sort="champ"` — tri par champ frontmatter (numérique : décroissant, texte : croissant)
- `template="grid|list|table"` — format de sortie (défaut : `grid`)
- `fields="champ1,champ2"` — colonnes pour `list` et `table`

```markdown
<!-- start-replace-frontmatter dir="./projets" filter="frontpage=1" sort="year_start" template="grid" -->
<!-- end-replace-frontmatter -->
```

---

**`60_generate_subnav.sh`**
Insère ou met à jour une sous-navigation (liens vers les sous-dossiers) entre les tags
`<!-- start-replace-subnav -->` et `<!-- end-replace-subnav -->` dans chaque `README.md`.
Supporte une image de couverture `_cover.png` / `_cover.jpg` dans les sous-dossiers.
Option `depth=N` dans le tag de début pour limiter la profondeur de récursion.

```markdown
<!-- start-replace-subnav depth=1 -->
<!-- end-replace-subnav -->
```

---

**`70_generate_sidebar.sh`**
Génère le contenu du `_sidebar.md` à la racine du dépôt.

**Mode tag** : si `_sidebar.md` contient un tag `start-replace-sidebar`, seul le contenu entre
les tags est remplacé. **Mode héritage** : si aucun tag, le fichier entier est réécrit.

Paramètres du tag :
- `dir="./chemin"` — dossier à parcourir (défaut : dossier du `_sidebar.md`)
- `maxdepth="N"` — profondeur maximale (défaut : illimitée)
- `filter="cle=valeur"` — filtre par champ frontmatter
- `sort="champ"` — tri par champ frontmatter
- `flat="true"` — liste à plat (non indentée)

Un fichier `.docshignore` dans un dossier exclut ce dossier et ses enfants.

```markdown
<!-- start-replace-sidebar maxdepth="6" sort="year_start" -->
<!-- end-replace-sidebar -->
```

---

**`75_generate_navbar.sh`**
Génère le contenu du `_navbar.md` à la racine du dépôt.
Si aucun `_navbar.md` n'existe, un nouveau fichier est créé.

Paramètres du tag :
- `dir="./chemin"` — dossier à parcourir (défaut : dossier du `_navbar.md`)
- `maxdepth="N"` — profondeur maximale (défaut : 1)
- `filter="cle=valeur"` — filtre par champ frontmatter (ex. `filter="navbar=1"`)
- `sort="champ"` — tri par champ frontmatter

Les entrées dont le frontmatter contient `navbar: 1` sont incluses. Une icône SVG
`_icon.svg` dans le dossier est automatiquement intégrée en base64 dans le lien.

```markdown
<!-- start-replace-navbar maxdepth="1" filter="navbar=1" -->
<!-- end-replace-navbar -->
```

---

**`80_generate_gitrepos.sh`**
Pour chaque `README.md` contenant un tag `start-replace-gitrepos`, récupère la liste des
dépôts publics depuis GitHub, GitLab ou Codeberg et insère un tableau Markdown.

Les résultats sont mis en cache localement (`.gitrepos-result-*.json`) et utilisés comme
solution de repli en cas d'échec de l'API.

Attributs du tag :
- `service="github|gitlab|codeberg"` — obligatoire
- `username="USER"` — dépôts d'un compte utilisateur
- `org="ORG"` — dépôts d'une organisation GitHub
- `group="chemin/groupe"` — dépôts d'un groupe GitLab
- `creator="LOGIN"` — filtre par auteur du premier commit (GitHub uniquement)
- `exclude="regex"` — masque les dépôts dont le nom ou la description correspond
- `heading="Titre"` — titre de section Markdown au-dessus du tableau

Variable d'environnement : `GITHUB_TOKEN` pour augmenter la limite de débit de l'API.

```markdown
<!-- start-replace-gitrepos service="github" username="moncompte" -->
<!-- end-replace-gitrepos -->

<!-- start-replace-gitrepos service="github" org="mon-org" creator="monlogin" exclude="^archive-" -->
<!-- end-replace-gitrepos -->
```

---

**`90_compile_typst.sh`**
Compile les fichiers `.typ` Typst en PDF. Ne recompile que si la source a été modifiée
depuis la dernière compilation (vérification par `mtime`).

---

**`autorun.sh`**
Exécute tous les scripts `.sh` du dossier `docsh` dans l'ordre alphabétique/numérique,
sauf lui-même. Affiche le temps d'exécution de chaque script.

---

### Usage rapide

```bash
# Exécuter tous les scripts depuis la racine du dépôt
bash docsh/autorun.sh

# Exécuter un script individuellement
bash docsh/70_generate_sidebar.sh
bash docsh/80_generate_gitrepos.sh
```

### Intégration CI/CD (GitLab)

Pour une reconstruction automatique chaque semaine :

1. Créer un **Project Access Token** (`Settings → Access Tokens`) avec le scope `write_repository`
2. L'ajouter comme variable CI `PUSH_TOKEN` (`Settings → CI/CD → Variables`)
3. Ajouter optionnellement `GITHUB_TOKEN` pour les appels API GitHub
4. Créer un **Scheduled Pipeline** (`CI/CD → Schedules`) avec le cron `0 4 * * 1` (lundi 04h UTC)

Le job `rebuild` dans `.gitlab-ci.yml` exécute `autorun.sh`, commite les fichiers modifiés et
pousse sur la branche principale — ce qui déclenche le déploiement Pages.

### Bonnes pratiques

- Exécuter depuis la racine du dépôt pour que les chemins relatifs fonctionnent.
- Rendre les scripts exécutables si besoin : `chmod +x docsh/*.sh`.
- Utiliser `.docshignore` pour exclure un dossier de la sidebar et de la subnav.
- Commiter les fichiers `.gitrepos-result-*.json` pour assurer la continuité en cas d'indisponibilité de l'API.

English / Anglais
------------------

`docsh` is a small collection of Bash scripts to help generate and maintain static
documentation (for example, Docsify). Scripts walk the project tree, generate `_sidebar.md`
and `_navbar.md`, insert sub-navigations into `README.md` files, fetch repository lists from
GitHub, GitLab and Codeberg, compile Typst documents, and manage media and file-list insertion.

Scripts are numbered and run in order via `autorun.sh`.

### Prerequisites

- `bash` 4+, `python3`, `git`
- `typst` — only required for `90_compile_typst.sh`
- `GITHUB_TOKEN` (optional) — avoids GitHub API rate limits in `80_generate_gitrepos.sh`

### Scripts

**`30_generate_media.sh`**
Replaces the block between `<!-- start-replace-media ... -->` and `<!-- end-replace-media -->`
with a list of images found in the directory's `medias/` folder.
`no-caption` flag: uses a space as alt text (no visible caption).

```markdown
<!-- start-replace-media -->
<!-- end-replace-media -->
```

---

**`35_generate_filelist.sh`**
Replaces the block between `<!-- start-replace-filelist ... -->` and `<!-- end-replace-filelist -->`
with a Markdown link list.

Default: lists all non-hidden contents of the README's own directory (files **and**
subdirectories), excluding `README.md` itself.

Tag parameters:
- `folder="./path"` — folder to scan (default: directory of the `README.md`)
- `pattern="regex"` — filter filenames by regex
- `recursive` *(flag)* — include subdirectories
- `raw` *(flag)* — use bare filenames instead of Title Case link text

```markdown
<!-- start-replace-filelist folder="./export" pattern="\.stl$" -->
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

**`50_generate_frontmatter_content.sh`**
Scans subdirectory `README.md` files for YAML frontmatter and generates formatted Markdown
content (image grid, list, or table) between `<!-- start-replace-frontmatter -->` tags.

Tag parameters:
- `dir="./path"` — directory to scan
- `filter="key=value"` — include only entries where frontmatter field equals value (e.g. `filter="frontpage=1"`)
- `sort="field"` — sort by frontmatter field (numeric → descending, text → ascending)
- `template="grid|list|table"` — output format (default: `grid`)
- `fields="field1,field2"` — columns for `list` and `table` templates

```markdown
<!-- start-replace-frontmatter dir="./projets" filter="frontpage=1" sort="year_start" template="grid" -->
<!-- end-replace-frontmatter -->
```

---

**`60_generate_subnav.sh`**
Inserts or updates a sub-navigation (links to subdirectories) between
`<!-- start-replace-subnav -->` and `<!-- end-replace-subnav -->` in each `README.md`.
Supports a `_cover.png` / `_cover.jpg` cover image in subdirectories.
Add `depth=N` to the start tag to limit recursion depth.

```markdown
<!-- start-replace-subnav depth=1 -->
<!-- end-replace-subnav -->
```

---

**`70_generate_sidebar.sh`**
Generates `_sidebar.md` content at the repository root.

**Tag mode**: if `_sidebar.md` contains a `start-replace-sidebar` tag, only the content between
tags is replaced. **Legacy mode**: if no tag, the whole file is rewritten.

Tag parameters:
- `dir="./path"` — directory to scan (default: directory of `_sidebar.md`)
- `maxdepth="N"` — stop recursing after N levels (default: unlimited)
- `filter="key=value"` — include only entries matching a frontmatter field
- `sort="field"` — sort siblings by frontmatter field
- `flat="true"` — emit a flat non-indented list

A `.docshignore` file in a directory excludes it and its children.

```markdown
<!-- start-replace-sidebar maxdepth="6" sort="year_start" -->
<!-- end-replace-sidebar -->
```

---

**`75_generate_navbar.sh`**
Generates `_navbar.md` content at the repository root.
If no `_navbar.md` exists, a new one is created.

Tag parameters:
- `dir="./path"` — directory to scan (default: directory of `_navbar.md`)
- `maxdepth="N"` — stop after N levels (default: 1)
- `filter="key=value"` — include only entries matching a frontmatter field (e.g. `filter="navbar=1"`)
- `sort="field"` — sort siblings by frontmatter field

Entries with `navbar: 1` in their frontmatter are included. An `_icon.svg` file in a directory
is automatically base64-embedded as an inline icon in the link.

```markdown
<!-- start-replace-navbar maxdepth="1" filter="navbar=1" -->
<!-- end-replace-navbar -->
```

---

**`80_generate_gitrepos.sh`**
For each `README.md` containing a `start-replace-gitrepos` tag, fetches the public repository
list from GitHub, GitLab, or Codeberg and inserts a Markdown table.

Results are cached locally (`.gitrepos-result-*.json`) and used as a fallback on API failure.
All providers are fetched in parallel.

Tag attributes:
- `service="github|gitlab|codeberg"` — required
- `username="USER"` — user account repositories
- `org="ORG"` — GitHub organisation repositories
- `group="path/group"` — GitLab group repositories
- `creator="LOGIN"` — filter by first-commit author (GitHub only)
- `exclude="regex"` — hide repos whose name or description matches
- `heading="Title"` — Markdown section heading above the table

Environment: `GITHUB_TOKEN` to raise the GitHub API rate limit (60 → 5 000 req/h).

```markdown
<!-- start-replace-gitrepos service="github" username="myaccount" -->
<!-- end-replace-gitrepos -->

<!-- start-replace-gitrepos service="github" org="my-org" creator="mylogin" exclude="^archive-" -->
<!-- end-replace-gitrepos -->
```

---

**`90_compile_typst.sh`**
Compiles Typst `.typ` source files to PDF. Skips files that are already up to date
(mtime-based check — no unnecessary recompilation).

---

**`autorun.sh`**
Runs all `.sh` scripts in the `docsh` folder in alphabetical/numeric order, skipping itself.
Prints elapsed time per script.

---

### Quick start

```bash
# Run all scripts from the repository root
bash docsh/autorun.sh

# Run a single script
bash docsh/70_generate_sidebar.sh
bash docsh/80_generate_gitrepos.sh
```

### CI/CD integration (GitLab)

For automatic weekly rebuilds:

1. Create a **Project Access Token** (`Settings → Access Tokens`) with `write_repository` scope
2. Add it as a CI variable `PUSH_TOKEN` (`Settings → CI/CD → Variables`)
3. Optionally add `GITHUB_TOKEN` for GitHub API calls
4. Create a **Scheduled Pipeline** (`CI/CD → Schedules`) with cron `0 4 * * 1` (Monday 04:00 UTC)

The `rebuild` job in `.gitlab-ci.yml` runs `autorun.sh`, commits any changed files, and pushes
to the main branch — triggering a Pages deployment.

### Notes

- Run from the repository root so relative paths behave as expected.
- Make scripts executable if preferred: `chmod +x docsh/*.sh`.
- Use `.docshignore` to exclude a directory from the sidebar and subnav.
- Commit `.gitrepos-result-*.json` files to ensure continuity when the API is unavailable.

License
-------
See the `LICENSE` file in the repository.

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
