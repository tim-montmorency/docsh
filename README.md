# docsh

Français / French
------------------

`docsh` est une petite collection de scripts Bash pour faciliter la génération et la maintenance
de la documentation statique (par exemple pour Docsify). Les scripts parcourent l'arborescence
du projet, génèrent un `_sidebar.md`, insèrent des sous-navigations dans les `README.md` et
gèrent l'insertion d'éléments médias (images) depuis des dossiers `medias/`.

Principaux scripts
- `10_generate_sidebar.sh` : génère un fichier `_sidebar.md` en se basant sur les titres
	des `README.md` trouvés dans les sous-répertoires.
- `20_generate_subnav.sh` : insère ou met à jour le contenu entre

- `30_generate_media.sh` : remplace le bloc entre
	`<!-- start-replace-media ... -->` et `<!-- end-replace-media -->` par une liste d'images
	provenant du dossier `medias/` du répertoire courant. Supporte l'option `no-caption`.
- `autorun.sh` : exécute les scripts présents dans le dossier `docsh` (sauf lui-même).

Usage rapide

Exécuter tous les scripts (depuis la racine du dépôt) :

```bash
bash ./autorun.sh
```

Ou exécuter un script individuellement :

```bash
bash ./10_generate_sidebar.sh
```

Bonnes pratiques
- Exécuter depuis la racine du dépôt pour que les chemins relatifs fonctionnent correctement.
- Rendre les scripts exécutables si vous préférez `./script.sh` : `chmod +x script.sh`.
- Installer `shellcheck` et `shfmt` si vous voulez vérifier et formater les scripts Bash.

English / Anglais
------------------

`docsh` is a small collection of Bash scripts to help generate and maintain static
documentation (for example, Docsify). The scripts walk the project tree, generate a
`_sidebar.md`, inject sub-navigation blocks into `README.md` files, and manage media
insertion (images) from `medias/` folders.

Main scripts
- `10_generate_sidebar.sh`: generates a `_sidebar.md` file based on the `#` titles found
	in `README.md` files under subdirectories.
- `20_generate_subnav.sh`: inserts or updates the content between

- `30_generate_media.sh`: replaces the block between
	`<!-- start-replace-media ... -->` and `<!-- end-replace-media -->` with a list of images
	found in the directory's `medias/` folder. Supports a `no-caption` mode.
- `autorun.sh`: runs all scripts in the `docsh` folder (skips itself).

Quick start

Run all scripts from the repository root:

```bash
bash ./autorun.sh
```

Or run a single script:

```bash
bash ./10_generate_sidebar.sh
```

Notes & Improvements
- Prefer running from the repository root so relative paths behave as expected.
- Consider adding `set -euo pipefail` and `shopt -s nullglob` to the scripts for
	more robust error handling, and use `find -print0` for filenames with spaces.
- Adding a GitHub Actions workflow to run `shellcheck` is recommended.

License
-------
See the `LICENSE` file in the repository.
