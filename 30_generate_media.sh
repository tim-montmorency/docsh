#!/bin/bash

# Fail on error, undefined vars, and fail pipelines; make globs return empty when no match
set -euo pipefail
shopt -s nullglob

# Répertoires à exclure de la génération de médias
EXCLUDED_DIRS=(".git" "node_modules" "__pycache__" ".vscode")

# Extensions de fichiers média supportées
SUPPORTED_EXTENSIONS=("jpg" "jpeg" "png" "gif" "svg" "webp")

# Répertoire racine (peut être passé en premier argument)
ROOT_DIR="${1:-$(pwd)}"

# Format le nom de fichier en un texte alternatif lisible
format_alt_text() {
    local filename="$1"
    # Supprime l'extension
    filename="${filename%.*}"
    # Remplace les underscores par des espaces
    filename="${filename//_/ }"
    
    # Supprime uniquement les 2 chiffres au début (s'ils sont suivis d'un espace)
    # Ne supprime pas les nombres à 4 chiffres (années) qui doivent rester dans le texte alt
    if [[ "$filename" =~ ^[0-9]{2}[^0-9]\ (.*) ]]; then
        # Extrait tout après les 2 chiffres
        filename="${BASH_REMATCH[1]}"
    fi
    
    # Met en majuscule la première lettre de chaque mot
    echo "$filename" | tr '[:upper:]' '[:lower:]' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1'
}

# Traitement des médias pour un répertoire unique
process_media_for_directory() {
    local dir_path="$1"
    local media_dir="$dir_path/medias"
    local readme_path="$dir_path/README.md"

    # Vérifie si le fichier README.md existe et si le dossier medias existe
    if [[ ! -f "$readme_path" || ! -d "$media_dir" ]]; then
        return
    fi

    echo "Traitement des médias dans : $dir_path"

    # Cherche les tags de remplacement avec ou sans arguments
    local start_tag_line
    start_tag_line=$(grep -n "<!-- start-replace-media" "$readme_path" | cut -d: -f1 | head -n 1)
    
    if [[ -z "$start_tag_line" ]]; then
        echo "Skipping $readme_path, no media replacement tags found."
        return
    fi

    # Extrait la ligne complète du tag de début pour analyser les arguments
    local start_tag_content
    start_tag_content=$(sed -n "${start_tag_line}p" "$readme_path")
    
    # Vérifie si l'argument no-caption est présent
    local no_caption=false
    if [[ "$start_tag_content" == *"no-caption"* ]]; then
        no_caption=true
        echo "Mode no-caption activé pour $readme_path (alt text = espace)"
    fi

    # Vérifie la présence du tag de fin
    if ! grep -q "<!-- end-replace-media -->" "$readme_path"; then
        echo "Skipping $readme_path, missing end tag."
        return
    fi

    # Génère la liste des médias avec ou sans texte alternatif
    local media_content=""

    # Ne traite que les fichiers avec extensions supportées dans le dossier medias
    # Use nullglob so the loop is skipped if there are no matches
    for media_file in "$media_dir"/*.*; do
        if [[ -f "$media_file" ]]; then
            local filename
            filename=$(basename "$media_file")
            local extension="${filename##*.}"
            extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
            
            # Vérifie si l'extension est supportée
            if [[ " ${SUPPORTED_EXTENSIONS[*]} " =~ " ${extension} " ]]; then
                if [[ "$no_caption" == true ]]; then
                    # Mode no-caption - utilise un espace comme texte alternatif
                    media_content+="* ![ ](./medias/${filename})"$'\n'
                else
                    # Mode normal - génère un texte alternatif formaté
                    local alt_text=$(format_alt_text "$filename")
                    media_content+="* ![${alt_text}](./medias/${filename})"$'\n'
                fi
            fi
        fi
    done

    # Remplace le contenu entre les tags
    if [[ -n "$start_tag_line" ]]; then
        # Trouver les numéros de ligne des balises
        local start_line
        start_line=$(grep -n "<!-- start-replace-media" "$readme_path" | cut -d: -f1 | head -n 1)
        local end_line
        end_line=$(grep -n "<!-- end-replace-media -->" "$readme_path" | cut -d: -f1 | head -n 1)

        # Si, pour une raison quelconque, start > end, saute
        if [[ -z "$start_line" || -z "$end_line" || $start_line -gt $end_line ]]; then
            echo "Skipping $readme_path, invalid tag order."
            return
        fi

        # Construit le fichier mis à jour
        sed -n "1,${start_line}p" "$readme_path" > "$readme_path.tmp"
        printf "%s\n" "$media_content" >> "$readme_path.tmp"
        sed -n "${end_line},\$p" "$readme_path" >> "$readme_path.tmp"

        mv "$readme_path.tmp" "$readme_path"
        echo "✅ Médias mis à jour dans $readme_path"
    else
        echo "Skipping $readme_path, media replacement tags not found."
    fi
}

# Traitement récursif de tous les répertoires
process_media_recursively() {
    local dir_path="$1"
    dir_path="${dir_path%/}"

    # Traite le répertoire courant
    process_media_for_directory "$dir_path"

    # Traite les sous-répertoires
    for subdir in "$dir_path"/*/; do
        if [[ -d "$subdir" ]]; then
            subdir="${subdir%/}"
            local base_dir
            base_dir=$(basename "$subdir")

            # Ignore les répertoires exclus
            if [[ ! " ${EXCLUDED_DIRS[*]} " =~ " ${base_dir} " ]]; then
                process_media_recursively "$subdir"
            fi
        fi
    done
}

# Démarre le traitement depuis le répertoire courant
process_media_recursively "$ROOT_DIR"
