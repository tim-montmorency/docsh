#!/bin/bash
# 80_generate_gitrepos.sh — Fetch repository lists from GitHub, GitLab, and Codeberg.
#
# For each README.md containing a <!-- start-replace-gitrepos ... --> tag,
# fetches the public repository list from the specified service and replaces the
# block with a markdown table (name · description · last push/activity date).
#
# Tag syntax:
#   <!-- start-replace-gitrepos service="github|gitlab|codeberg" username="USER" -->
#   ...generated content replaced on each run...
#   <!-- end-replace-gitrepos -->
#
# Requires: curl, python3 (3.6+)

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="${1:-$DEFAULT_ROOT}"

# ---------------------------------------------------------------------------
# Fetch raw JSON from the service API into stdout.
# Falls back to an empty result on network errors so the script stays non-fatal.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# GitLab helper: paginate any endpoint that uses X-Total-Pages header.
# Usage: fetch_gitlab_paginated <url_without_page_param>
# ---------------------------------------------------------------------------
fetch_gitlab_paginated() {
    python3 - "$1" <<'PYEOF'
import sys, json, math, urllib.request

base_url = sys.argv[1]
headers  = {"User-Agent": "docsh-gitrepos/1.0"}
all_repos = []
page = 1
while True:
    url = f"{base_url}&page={page}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            total_pages = int(r.headers.get("X-Total-Pages", "1") or "1")
            batch = json.load(r)
    except Exception as e:
        sys.stderr.write(f"GitLab fetch error (page {page}): {e}\n")
        break
    all_repos.extend(batch)
    if page >= total_pages:
        break
    page += 1
print(json.dumps(all_repos))
PYEOF
}

fetch_repos() {
    local service="$1" username="$2" group="$3"
    case "$service" in
        github)
            curl -sf --max-time 15 \
                -H "Accept: application/vnd.github.v3+json" \
                -H "User-Agent: docsh-gitrepos/1.0" \
                "https://api.github.com/users/${username}/repos?sort=pushed&per_page=100" \
                || echo "[]"
            ;;
        gitlab)
            if [[ -n "$group" ]]; then
                # Group (+ all subgroups) mode
                fetch_gitlab_paginated \
                    "https://gitlab.com/api/v4/groups/${group}/projects?include_subgroups=true&order_by=last_activity_at&sort=desc&per_page=100&visibility=public"
            else
                # User repos mode — resolve numeric ID first
                local uid
                uid=$(curl -sf --max-time 10 \
                    "https://gitlab.com/api/v4/users?username=${username}" \
                    | python3 -c "
import sys, json
try:
    u = json.load(sys.stdin)
    print(u[0]['id'] if u else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
                if [[ -z "$uid" ]]; then
                    echo "  Warning: could not resolve GitLab user ID for @$username" >&2
                    echo "[]"
                    return
                fi
                fetch_gitlab_paginated \
                    "https://gitlab.com/api/v4/users/${uid}/projects?order_by=last_activity_at&sort=desc&per_page=100&visibility=public"
            fi
            ;;
        codeberg)
            # Codeberg/Gitea: use users/{username}/repos (not repos/search which
            # is a global text search). Response is a plain JSON array.
            # X-Total-Count header gives the exact total; paginate accordingly.
            python3 - "$username" <<'PYEOF'
import sys, json, math, urllib.request

username = sys.argv[1]
base = f"https://codeberg.org/api/v1/users/{username}/repos"
headers = {"User-Agent": "docsh-gitrepos/1.0"}

# First page — also read X-Total-Count to know how many pages to fetch
url = f"{base}?limit=50&sort=updated&order=desc&page=1"
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        total = int(r.headers.get("X-Total-Count", "0"))
        batch = json.load(r)
except Exception as e:
    sys.stderr.write(f"Codeberg fetch error: {e}\n")
    print("[]"); sys.exit(0)

all_repos = list(batch)
total_pages = math.ceil(total / 50)

for page in range(2, total_pages + 1):
    url = f"{base}?limit=50&sort=updated&order=desc&page={page}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            all_repos.extend(json.load(r))
    except Exception:
        break

print(json.dumps({"data": all_repos}))
PYEOF
            ;;
        *)
            echo "[]"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Read JSON from $2 (file path), format as a markdown table, write to stdout.
# The Python script is supplied via heredoc (stdin to python3 -).
# ---------------------------------------------------------------------------
format_repos() {
    local service="$1" json_file="$2" group="${3:-}"
    python3 - "$service" "$json_file" "$group" <<'PYEOF'
import sys, json

service   = sys.argv[1]
json_file = sys.argv[2]
group     = sys.argv[3] if len(sys.argv) > 3 else ""

try:
    with open(json_file) as f:
        payload = json.load(f)
except Exception:
    payload = []

if service == "codeberg":
    repos = payload.get("data", []) if isinstance(payload, dict) else []
elif isinstance(payload, list):
    repos = payload
else:
    repos = []

if not repos:
    print("*No public repositories found.*")
    sys.exit(0)

if service == "github":
    col = "Last push"
    def row(r):
        name = r.get("name", "")
        desc = " ".join((r.get("description") or "").split()).replace("|", "\\|")
        url  = r.get("html_url", "")
        date = (r.get("pushed_at") or "")[:10] or "—"
        fork = " *(fork)*" if r.get("fork") else ""
        site = r.get("homepage") or ""
        prefix = f"[↗]({site}) " if site else ""
        return f"| [{name}]({url}){fork} | {(prefix + desc).strip()} | {date} |"
    repos = sorted(repos, key=lambda x: x.get("pushed_at", ""), reverse=True)
    header = f"| Repository | Description | {col} |"
    sep    =  "|---|---|---|"

elif service == "gitlab":
    col = "Last activity"
    def pages_url(r):
        if r.get("pages_access_level") != "enabled":
            return ""
        parts = r.get("path_with_namespace", "").split("/")
        return f"https://{parts[0]}.gitlab.io/{'/'.join(parts[1:])}/" if len(parts) > 1 else ""
    if group:
        def row(r):
            name = r.get("name", "")
            desc = " ".join((r.get("description") or "").split()).replace("|", "\\|")
            url  = r.get("web_url", "")
            date = (r.get("last_activity_at") or "")[:10] or "—"
            fork = " *(fork)*" if r.get("forked_from_project") else ""
            ns   = r.get("namespace") or {}
            ns_path = ns.get("full_path", "")
            ns_url  = ns.get("web_url", "")
            ns_cell = f"[{ns_path}]({ns_url})" if ns_url else ns_path
            site = pages_url(r)
            prefix = f"[↗]({site}) " if site else ""
            return f"| [{name}]({url}){fork} | {(prefix + desc).strip()} | {ns_cell} | {date} |"
        header = f"| Repository | Description | Group | {col} |"
        sep    =  "|---|---|---|---|"
    else:
        def row(r):
            name = r.get("name", "")
            desc = " ".join((r.get("description") or "").split()).replace("|", "\\|")
            url  = r.get("web_url", "")
            date = (r.get("last_activity_at") or "")[:10] or "—"
            fork = " *(fork)*" if r.get("forked_from_project") else ""
            site = pages_url(r)
            prefix = f"[↗]({site}) " if site else ""
            return f"| [{name}]({url}){fork} | {(prefix + desc).strip()} | {date} |"
        header = f"| Repository | Description | {col} |"
        sep    =  "|---|---|---|"

elif service == "codeberg":
    col = "Last updated"
    def row(r):
        name = r.get("name", "")
        desc = " ".join((r.get("description") or "").split()).replace("|", "\\|")
        url  = r.get("html_url", "")
        date = (r.get("updated_at") or "")[:10] or "—"
        fork = " *(fork)*" if r.get("fork") else ""
        site = r.get("website") or ""
        prefix = f"[↗]({site}) " if site else ""
        return f"| [{name}]({url}){fork} | {(prefix + desc).strip()} | {date} |"
    repos = sorted(repos, key=lambda x: x.get("updated_at", ""), reverse=True)
    header = f"| Repository | Description | {col} |"
    sep    =  "|---|---|---|"

else:
    print("*Unknown service.*")
    sys.exit(0)

print(header)
print(sep)
for r in repos:
    print(row(r))
PYEOF
}

# ---------------------------------------------------------------------------
# Process a single README.md: find every start-replace-gitrepos block,
# fetch + format the repo list, and splice it in (bottom-to-top pass).
# ---------------------------------------------------------------------------
process_gitrepos_for_readme() {
    local readme_path="$1"
    grep -q "<!-- start-replace-gitrepos" "$readme_path" || return 0

    echo "Processing git repos in: $readme_path"

    local start_lines=()
    while IFS= read -r ln; do
        start_lines+=("$ln")
    done < <(grep -n "<!-- start-replace-gitrepos" "$readme_path" | cut -d: -f1)

    local i
    for (( i=${#start_lines[@]}-1; i>=0; i-- )); do
        local start_ln="${start_lines[$i]}"
        local tag_line
        tag_line="$(sed -n "${start_ln}p" "$readme_path")"

        local service="" username="" group=""
        [[ "$tag_line" =~ service=\"([^\"]+)\" ]]   && service="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ username=\"([^\"]+)\" ]]  && username="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ group=\"([^\"]+)\" ]]     && group="${BASH_REMATCH[1]}"

        if [[ -z "$service" || ( -z "$username" && -z "$group" ) ]]; then
            echo "  Skipping block at line $start_ln: missing service or username/group"
            continue
        fi

        local end_ln
        end_ln="$(awk -v s="$start_ln" \
            'NR>s && /<!-- end-replace-gitrepos -->/{print NR; exit}' "$readme_path")"

        if [[ -z "$end_ln" ]]; then
            echo "  Warning: no end tag found for block starting at line $start_ln"
            continue
        fi

        local label=""
        [[ -n "$group" ]]    && label="group:$group" || label="@$username"
        echo "  Fetching $service repos for $label..."

        local json_tmp content_tmp
        json_tmp="$(mktemp)"
        content_tmp="$(mktemp)"

        fetch_repos   "$service" "$username" "$group" > "$json_tmp"
        format_repos  "$service" "$json_tmp" "$group" > "$content_tmp"
        rm -f "$json_tmp"

        {
            sed -n "1,${start_ln}p" "$readme_path"
            cat "$content_tmp"
            sed -n "${end_ln},\$p" "$readme_path"
        } > "$readme_path.tmp"
        mv "$readme_path.tmp" "$readme_path"

        rm -f "$content_tmp"
        echo "  Updated: $readme_path ($service/$label)"
    done
}

# ---------------------------------------------------------------------------
# Walk the repo, skipping generated / vendor / tool directories.
# ---------------------------------------------------------------------------
find "$ROOT_DIR" -name "README.md" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/docsh/*" \
    -not -path "*/_site/*" \
    -not -path "*/vendor/*" \
    | while IFS= read -r readme; do
        process_gitrepos_for_readme "$readme"
    done
