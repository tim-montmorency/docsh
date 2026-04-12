#!/bin/bash
# 80_generate_gitrepos.sh — Fetch repository lists from GitHub, GitLab, and Codeberg.
#
# For each README.md containing a <!-- start-replace-gitrepos ... --> tag,
# fetches the public repository list from the specified service and replaces the
# block with a markdown table (name · description · last push/activity date).
#
# Tag syntax:
#   <!-- start-replace-gitrepos service="github|gitlab|codeberg" username="USER" -->
#   <!-- start-replace-gitrepos service="github" org="ORG" [exclude="REGEX"] -->
#   ...generated content replaced on each run...
#   <!-- end-replace-gitrepos -->
#
# Attributes:
#   service   required  github | gitlab | codeberg
#   username  —         user account repos (github/gitlab/codeberg)
#   org       —         GitHub organisation repos (replaces username)
#   group     —         GitLab group path
#   subgroup  —         GitLab subgroup within group (combined as group/subgroup)
#   exclude   —         Python regex; repos whose name matches are hidden
#                       e.g. exclude="^(c[0-9]-|momo_modele)" to skip student repos
#
# Environment:
#   GITHUB_TOKEN   optional  Personal access token; raises the GitHub API rate
#                            limit from 60 to 5 000 req/h.  Set in shell or
#                            export from your CI environment.
#
# Requires: curl, python3 (3.6+)
#
# Usage:
#   bash docsh/80_generate_gitrepos.sh [DIR]
#     DIR  root of the tree to search (default: parent of the docsh/ folder)
#
#   Called automatically by docsh/autorun.sh.

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="${1:-$DEFAULT_ROOT}"

# Caches are stored per-directory alongside the README.md that uses them:
#   .gitrepos-creator-cache.json  — first-commit author lookups (GitHub creator= filter)
#   .gitrepos-result-<service>-<target>.json — last successful fetch; used as
#                                              fallback when the API is unavailable.

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
    local service="$1" username="$2" group="$3" org="${4:-}" creator="${5:-}" exclude="${6:-}" cache_dir="${7:-$ROOT_DIR}"
    local _creator_cache="${cache_dir}/.gitrepos-creator-cache.json"
    case "$service" in
        github)
            if [[ -n "$org" ]]; then
                # Org mode — fetch all public org repos (paginated), then:
                #   1. Pre-filter by exclude regex (name + description) — cheap, no extra calls
                #   2. If creator= set: check first commit author (2 calls/repo)
                #      Requires GITHUB_TOKEN — aborts cleanly if rate limited.
                python3 - "$org" "$creator" "$exclude" "$_creator_cache" <<'PYEOF'
import sys, json, os, re as _re, urllib.request

org        = sys.argv[1]
creator    = sys.argv[2].lower()  # may be empty string
exclude    = sys.argv[3]          # may be empty string
cache_path = sys.argv[4] if len(sys.argv) > 4 else ""

headers = {
    "Accept":     "application/vnd.github.v3+json",
    "User-Agent": "docsh-gitrepos/1.0",
}
token = os.environ.get("GITHUB_TOKEN", "")
if token:
    headers["Authorization"] = f"token {token}"

all_repos = []
page = 1
while True:
    url = (f"https://api.github.com/orgs/{org}/repos"
           f"?sort=pushed&per_page=100&page={page}")
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            batch = json.load(r)
    except Exception as e:
        sys.stderr.write(f"GitHub fetch error (org repos, page {page}): {e}\n")
        break
    if not batch:
        break
    all_repos.extend(batch)
    if len(batch) < 100:
        break
    page += 1

# ── Step 1: pre-filter by exclude regex (name + description) ──────────────────
# Done here (not just in format_repos) so creator= has fewer repos to check.
if exclude:
    pat = _re.compile(exclude, _re.IGNORECASE)
    before = len(all_repos)
    all_repos = [
        r for r in all_repos
        if not pat.search(r.get("name", "") or "")
        and not pat.search(r.get("description", "") or "")
    ]
    sys.stderr.write(f"  exclude filter: {before} → {len(all_repos)} repos\n")

# ── Step 2: first-commit author filter ──────────────────────────────────────
# Load persistent cache — first commits never change, so already-checked repos
# cost 0 API calls on every run after the first.
if creator:
    cache = {}
    if cache_path:
        try:
            with open(cache_path) as f:
                cache = json.load(f)
        except Exception:
            cache = {}

    def first_commit_author(full_name):
        """Return (github_login, git_name) of the repo's first-ever commit.
        Returns (None, None) on error; raises RuntimeError on rate limit."""
        url = f"https://api.github.com/repos/{full_name}/commits?per_page=1"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                link    = r.headers.get("Link", "")
                commits = json.load(r)
                last_url = None
                for part in link.split(","):
                    part = part.strip()
                    if 'rel="last"' in part:
                        m = _re.match(r'<([^>]+)>', part)
                        if m:
                            last_url = m.group(1)
                if last_url:
                    req2 = urllib.request.Request(last_url, headers=headers)
                    with urllib.request.urlopen(req2, timeout=15) as r2:
                        commits = json.load(r2)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                raise RuntimeError(
                    f"Rate limit hit ({e.code}). "
                    "Set GITHUB_TOKEN=ghp_xxx and re-run."
                )
            sys.stderr.write(f"  first-commit fetch error ({full_name}): {e}\n")
            return None, None
        except Exception as e:
            sys.stderr.write(f"  first-commit fetch error ({full_name}): {e}\n")
            return None, None
        if not commits:
            return None, None
        c = commits[0]
        login = (c.get("author") or {}).get("login", "") or ""
        name  = ((c.get("commit") or {}).get("author") or {}).get("name", "") or ""
        return login.lower(), name.lower()

    cached_hits = 0
    uncached    = []
    filtered    = []
    for r in all_repos:
        full = r["full_name"]
        if full in cache:
            cached_hits += 1
            e = cache[full]
            if creator in (e.get("login", ""), e.get("name", "")):
                filtered.append(r)
        else:
            uncached.append(r)

    if cached_hits:
        sys.stderr.write(f"  first-commit cache: {cached_hits} hits, {len(uncached)} to fetch\n")
    if uncached:
        sys.stderr.write(
            f"  Checking first-commit author for {len(uncached)} repos"
            f" (looking for '{creator}')...\n"
        )

    cache_dirty = False
    try:
        for r in uncached:
            login, name = first_commit_author(r["full_name"])
            cache[r["full_name"]] = {"login": login or "", "name": name or ""}
            cache_dirty = True
            if creator in (login, name):
                filtered.append(r)
    except RuntimeError as e:
        sys.stderr.write(f"  Aborting creator= check: {e}\n")
        all_repos = filtered
        if cache_dirty and cache_path:
            try:
                with open(cache_path, "w") as f:
                    json.dump(cache, f, indent=2)
            except Exception:
                pass
        print(json.dumps(all_repos))
        sys.exit(0)

    if uncached:
        sys.stderr.write(f"  {len(filtered)}/{len(all_repos)} repos match creator '{creator}'\n")

    if cache_dirty and cache_path:
        try:
            with open(cache_path, "w") as f:
                json.dump(cache, f, indent=2)
            sys.stderr.write(f"  Cache updated ({len(cache)} entries)\n")
        except Exception as e:
            sys.stderr.write(f"  Warning: could not write cache: {e}\n")

    all_repos = filtered

print(json.dumps(all_repos))
PYEOF
            else
                # User repos mode — Python for pagination, token support, and graceful rate-limit handling
                python3 - "$username" <<'PYEOF'
import sys, json, os, urllib.request

username = sys.argv[1]
headers = {
    "Accept":     "application/vnd.github.v3+json",
    "User-Agent": "docsh-gitrepos/1.0",
}
token = os.environ.get("GITHUB_TOKEN", "")
if token:
    headers["Authorization"] = f"token {token}"

all_repos = []
page = 1
while True:
    url = (f"https://api.github.com/users/{username}/repos"
           f"?sort=pushed&per_page=100&page={page}")
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            batch = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429):
            sys.stderr.write(
                f"  Warning: GitHub API rate limit hit for @{username} —"
                " set GITHUB_TOKEN=ghp_xxx and re-run.\n"
            )
        else:
            sys.stderr.write(f"  GitHub API error for @{username}: {e}\n")
        break
    except Exception as e:
        sys.stderr.write(f"  GitHub fetch error for @{username}: {e}\n")
        break
    if not batch:
        break
    all_repos.extend(batch)
    if len(batch) < 100:
        break
    page += 1

print(json.dumps(all_repos))
PYEOF
            fi
            ;;
        gitlab)
            if [[ -n "$group" ]]; then
                # Group (+ all subgroups) mode — URL-encode the group path
                # so nested subgroups (e.g. sr-expo/artwork) work correctly.
                local encoded_group="${group//\//%2F}"
                fetch_gitlab_paginated \
                    "https://gitlab.com/api/v4/groups/${encoded_group}/projects?include_subgroups=true&order_by=last_activity_at&sort=desc&per_page=100&visibility=public"
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
# Read JSON from $2 (file path), format as repo cards, download cover/icon
# images to .covers/ subfolder.  Writes markdown to stdout.
# $4 = exclude regex (optional)   — repos matching it are dropped (safety net)
# $5 = readme directory            — covers saved to $5/.covers/
# ---------------------------------------------------------------------------
format_repos() {
    local service="$1" json_file="$2" group="${3:-}" exclude="${4:-}" readme_dir="${5:-}"
    python3 - "$service" "$json_file" "$group" "$exclude" "$readme_dir" <<'PYEOF'
import sys, json, re, os, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

service       = sys.argv[1]
json_file     = sys.argv[2]
group         = sys.argv[3] if len(sys.argv) > 3 else ""
exclude       = sys.argv[4] if len(sys.argv) > 4 else ""
readme_dir    = sys.argv[5] if len(sys.argv) > 5 else ""
covers_dir    = os.path.join(readme_dir, ".covers") if readme_dir else ""

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

# Safety-net exclude filter (primary filter already ran in fetch_repos for orgs)
if exclude:
    pat = re.compile(exclude, re.IGNORECASE)
    repos = [
        r for r in repos
        if not pat.search(r.get("name", "") or "")
        and not pat.search(r.get("description", "") or "")
        and not pat.search(r.get("path", "") or "")
    ]

if not repos:
    print("*No public repositories found.*")
    sys.exit(0)

lines = []

# ── Cover / icon download ────────────────────────────────────────────────
CANDIDATE_SET = {
    '_cover.jpg', '_cover.webp', '_cover.png',
    'icon.webp', 'icon.svg', 'icon.jpg', 'icon.png',
}
# Priority order: prefer cover over icon, prefer jpg/webp over png/svg
CANDIDATE_PRIORITY = [
    '_cover.jpg', '_cover.webp', '_cover.png',
    'icon.webp', 'icon.svg', 'icon.jpg', 'icon.png',
]
CACHED_EXTS = ('.jpg', '.webp', '.png', '.svg')

_gh_headers = {"User-Agent": "docsh/1.0", "Accept": "application/vnd.github.v3+json"}
_gh_token = os.environ.get("GITHUB_TOKEN", "")
if _gh_token:
    _gh_headers["Authorization"] = f"token {_gh_token}"

def list_root_files(service, r):
    """Use the service API to list files in the repo root.  Returns a set of
    filenames, or None on error (caller falls back to blind probing)."""
    try:
        if service == "github":
            url = f"https://api.github.com/repos/{r.get('full_name','')}/contents/"
            req = urllib.request.Request(url, headers=_gh_headers)
        elif service == "gitlab":
            pid = r.get("id", "")
            url = f"https://gitlab.com/api/v4/projects/{pid}/repository/tree?per_page=100"
            req = urllib.request.Request(url, headers={"User-Agent": "docsh/1.0"})
        elif service == "codeberg":
            url = f"https://codeberg.org/api/v1/repos/{r.get('full_name','')}/contents/"
            req = urllib.request.Request(url, headers={"User-Agent": "docsh/1.0"})
        else:
            return None
        with urllib.request.urlopen(req, timeout=8) as resp:
            items = json.load(resp)
        return {
            item.get("name") or item.get("path", "").split("/")[-1]
            for item in items if isinstance(item, dict)
        }
    except Exception:
        return None

def raw_base(service, r):
    if service == "github":
        return f"https://raw.githubusercontent.com/{r.get('full_name', '')}/HEAD/"
    elif service == "gitlab":
        return f"https://gitlab.com/{r.get('path_with_namespace', '')}/-/raw/HEAD/"
    elif service == "codeberg":
        branch = r.get("default_branch", "main") or "main"
        return f"https://codeberg.org/{r.get('full_name', '')}/raw/branch/{branch}/"
    return ""

def nocover_svg(name):
    d = name[:30] + ('\u2026' if len(name) > 30 else '')
    d = d.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180">'
            f'<rect width="320" height="180" fill="#2a2a3a" rx="4"/>'
            f'<text x="160" y="95" text-anchor="middle" fill="#8b8acb" '
            f'font-size="14" font-family="sans-serif">{d}</text></svg>')

def safe_name(name):
    return re.sub(r'[^A-Za-z0-9._-]', '-', name)

def existing_cover(name, cdir):
    """Return cached path only for real covers (not nocover placeholders).
    Nocover repos are always re-checked via the API on every run."""
    sn = safe_name(name)
    for ext in CACHED_EXTS:
        p = os.path.join(cdir, sn + ext)
        if os.path.isfile(p):
            return f".covers/{sn}{ext}"
    return None

def download_cover(service, r, cdir, root_files):
    """Download the best cover/icon image for a repo.
    root_files: set of filenames in repo root (from list_root_files),
                or None to fall back to blind probing."""
    name = r.get("name", "")
    if not name or not cdir:
        return ""
    sn = safe_name(name)
    cached = existing_cover(name, cdir)
    if cached:
        return cached

    # Determine which candidate to download
    target = None
    if root_files is not None:
        hits = CANDIDATE_SET & root_files
        if hits:
            for c in CANDIDATE_PRIORITY:
                if c in hits:
                    target = c
                    break
        if not target:
            # API confirmed: no cover/icon exists
            dest = os.path.join(cdir, sn + "_nocover.svg")
            with open(dest, 'w') as f:
                f.write(nocover_svg(name))
            sys.stderr.write(f"    . {name} (no cover)\n")
            retry = os.path.join(cdir, sn + ".retry")
            if os.path.isfile(retry):
                os.remove(retry)
            return f".covers/{sn}_nocover.svg"

    base = raw_base(service, r)
    candidates = [target] if target else CANDIDATE_PRIORITY

    all_404 = True
    for candidate in candidates:
        url = base + candidate
        ext = os.path.splitext(candidate)[1]
        dest = os.path.join(cdir, sn + ext)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "docsh/1.0"})
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = resp.read()
                if data:
                    with open(dest, 'wb') as f:
                        f.write(data)
                    sys.stderr.write(f"    + {name} <- {candidate}\n")
                    retry = os.path.join(cdir, sn + ".retry")
                    if os.path.isfile(retry):
                        os.remove(retry)
                    return f".covers/{sn}{ext}"
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = min(int(e.headers.get('Retry-After', '30') or '30'), 90)
                sys.stderr.write(f"    ~ {name}: rate limited, wait {wait}s\n")
                time.sleep(wait + 1)
                all_404 = False
                break
            if e.code != 404:
                all_404 = False
        except Exception:
            all_404 = False
            continue

    dest = os.path.join(cdir, sn + "_nocover.svg")
    with open(dest, 'w') as f:
        f.write(nocover_svg(name))
    if all_404:
        sys.stderr.write(f"    . {name} (no cover)\n")
        retry = os.path.join(cdir, sn + ".retry")
        if os.path.isfile(retry):
            os.remove(retry)
    else:
        open(os.path.join(cdir, sn + ".retry"), 'w').close()
        sys.stderr.write(f"    ! {name} (retry later)\n")
    return f".covers/{sn}_nocover.svg"

cover_map = {}
if covers_dir:
    os.makedirs(covers_dir, exist_ok=True)

    # Phase 1: list root files for all repos (parallel) — 1 API call each
    sys.stderr.write(f"  Listing root files ({len(repos)} repos)...\n")
    file_lists = {}
    def _list(r):
        n = r.get("name", "")
        if existing_cover(n, covers_dir):
            return  # already cached, skip API call
        file_lists[n] = list_root_files(service, r)
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(_list, repos))

    # Phase 2: download only confirmed covers (parallel)
    need_dl = [r for r in repos if not existing_cover(r.get("name",""), covers_dir)]
    if need_dl:
        sys.stderr.write(f"  Downloading covers ({len(need_dl)} new)...\n")
    def _dl(r):
        n = r.get("name", "")
        root = file_lists.get(n)
        cover_map[n] = download_cover(service, r, covers_dir, root)
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(_dl, repos))

def repo_item(name, url, cover, date, site, fork, desc):
    """Emit a list item: image-link + metadata HTML comment.
    Format consumed by docsify-gitrepos.js and docsify-remote-repo.js.
    """
    safe_desc = desc.replace('"', '&quot;') if desc else ""
    meta = f'date="{date}"'
    if site:
        meta += f' site="{site}"'
    if safe_desc:
        meta += f' desc="{safe_desc}"'
    if fork:
        meta += ' fork'
    return f"* [![{name}]({cover})]({url} ':repo') <!-- gr {meta} -->"

if service == "github":
    repos = sorted(repos, key=lambda x: x.get("pushed_at", ""), reverse=True)
    for r in repos:
        name = r.get("name", "")
        url  = r.get("html_url", "")
        date = (r.get("pushed_at") or "")[:10] or "—"
        desc = " ".join((r.get("description") or "").split())
        site = r.get("homepage") or ""
        fork = r.get("fork", False)
        cover = cover_map.get(name, "")
        lines.append(repo_item(name, url, cover, date, site, fork, desc))

elif service == "gitlab":
    def pages_url(r):
        if r.get("pages_access_level") != "enabled":
            return ""
        parts = r.get("path_with_namespace", "").split("/")
        return f"https://{parts[0]}.gitlab.io/{'/'.join(parts[1:])}/" if len(parts) > 1 else ""
    for r in repos:
        name = r.get("name", "")
        url  = r.get("web_url", "")
        date = (r.get("last_activity_at") or "")[:10] or "—"
        desc = " ".join((r.get("description") or "").split())
        site = pages_url(r)
        fork = bool(r.get("forked_from_project"))
        if group:
            ns = r.get("namespace") or {}
            ns_path = ns.get("full_path", "")
            if ns_path and ns_path != group:
                desc = (desc + f" — {ns_path}") if desc else ns_path
        cover = cover_map.get(name, "")
        lines.append(repo_item(name, url, cover, date, site, fork, desc))

elif service == "codeberg":
    repos = sorted(repos, key=lambda x: x.get("updated_at", ""), reverse=True)
    for r in repos:
        name = r.get("name", "")
        url  = r.get("html_url", "")
        date = (r.get("updated_at") or "")[:10] or "—"
        desc = " ".join((r.get("description") or "").split())
        site = r.get("website") or ""
        fork = r.get("fork", False)
        cover = cover_map.get(name, "")
        lines.append(repo_item(name, url, cover, date, site, fork, desc))

else:
    print("*Unknown service.*")
    sys.exit(0)

print("\n".join(lines).rstrip())
PYEOF
}

# ---------------------------------------------------------------------------
# Process a single README.md: find every start-replace-gitrepos block,
# fetch + format the repo list, and splice it in (bottom-to-top pass).
# ---------------------------------------------------------------------------
process_gitrepos_for_readme() {
    local readme_path="$1"
    grep -q "<!-- start-replace-gitrepos" "$readme_path" || return 0

    echo "Processing: ${readme_path#${ROOT_DIR}/}"

    local start_lines=()
    while IFS= read -r ln; do
        start_lines+=("$ln")
    done < <(grep -n "<!-- start-replace-gitrepos" "$readme_path" | cut -d: -f1)

    local i
    for (( i=${#start_lines[@]}-1; i>=0; i-- )); do
        local start_ln="${start_lines[$i]}"
        local tag_line
        tag_line="$(sed -n "${start_ln}p" "$readme_path")"

        local service="" username="" group="" org="" exclude="" creator="" subgroup=""
        [[ "$tag_line" =~ service=\"([^\"]+)\" ]]   && service="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ username=\"([^\"]+)\" ]]  && username="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ group=\"([^\"]+)\" ]]     && group="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ org=\"([^\"]+)\" ]]       && org="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ exclude=\"([^\"]+)\" ]]   && exclude="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ creator=\"([^\"]+)\" ]]   && creator="${BASH_REMATCH[1]}"
        [[ "$tag_line" =~ subgroup=\"([^\"]+)\" ]]  && subgroup="${BASH_REMATCH[1]}"

        # Combine group + subgroup into a single group path
        if [[ -n "$subgroup" && -n "$group" ]]; then
            group="${group}/${subgroup}"
        fi

        if [[ -z "$service" || ( -z "$username" && -z "$group" && -z "$org" ) ]]; then
            echo "  Skipping block at line $start_ln: missing service or username/group/org"
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
        if [[ -n "$org" ]]; then
            label="${org}${creator:+ creator:$creator}${exclude:+ (exclude: $exclude)}"
        elif [[ -n "$group" ]]; then
            label="group:$group"
        else
            label="@$username"
        fi
        echo "  Fetching $service repos for $label..."

        local readme_dir
        readme_dir="$(dirname "$readme_path")"

        local json_tmp content_tmp
        json_tmp="$(mktemp)"
        content_tmp="$(mktemp)"

        fetch_repos "$service" "$username" "$group" "$org" "$creator" "$exclude" "$readme_dir" > "$json_tmp"

        # Result cache: save on success; restore on empty/failed fetch so we never
        # show "*No public repositories found.*" due to a transient API failure.
        local cache_key="${org:-${group:-${username:-unknown}}}"
        cache_key="${cache_key//\//-}"
        local result_cache
        result_cache="${readme_dir}/.gitrepos-result-${service}-${cache_key}.json"
        local _is_empty
        _is_empty=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    repos = d.get('data', d) if isinstance(d, dict) else d
    print('1' if not repos else '0')
except Exception:
    print('1')
" "$json_tmp")
        if [[ "$_is_empty" == "0" ]]; then
            cp "$json_tmp" "$result_cache"
        elif [[ -f "$result_cache" ]]; then
            echo "  Warning: API returned no repos for $label — using cached result"
            cp "$result_cache" "$json_tmp"
        fi

        format_repos  "$service" "$json_tmp" "$group" "$exclude" "$readme_dir" > "$content_tmp"
        rm -f "$json_tmp"

        {
            sed -n "1,${start_ln}p" "$readme_path"
            cat "$content_tmp"
            sed -n "${end_ln},\$p" "$readme_path"
        } > "$readme_path.tmp"
        mv "$readme_path.tmp" "$readme_path"

        rm -f "$content_tmp"
        echo "  Updated: ${readme_path#${ROOT_DIR}/} ($service/$label)"
    done
}

# ---------------------------------------------------------------------------
# Walk the repo, skipping generated / vendor / tool directories.
# ---------------------------------------------------------------------------
# Run each README in parallel; collect output per-process then print atomically.
_pids=()
_outs=()
while IFS= read -r readme; do
    _t=$(mktemp)
    _outs+=("$_t")
    process_gitrepos_for_readme "$readme" >"$_t" 2>&1 &
    _pids+=($!)
done < <(find "$ROOT_DIR" -name "README.md" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/docsh/*" \
    -not -path "*/_site/*" \
    -not -path "*/vendor/*")

for i in "${!_pids[@]}"; do
    wait "${_pids[$i]}"
    cat "${_outs[$i]}"
    rm -f "${_outs[$i]}"
done
