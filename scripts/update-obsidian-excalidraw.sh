#!/usr/bin/env bash
# Bump the pinned Obsidian Excalidraw plugin in users/martin/home.nix to the
# latest release. It's three plain fetchurl assets, so nix-prefetch-url is the
# whole verification; no build needed.
#
# Usage:  ./scripts/update-obsidian-excalidraw.sh
# Deps:   bash, curl, jq, nix (nix-prefetch-url)
set -euo pipefail

cd "$(dirname "$0")/.."
PKG="users/martin/home.nix"
REPO_SLUG="zsviczian/obsidian-excalidraw-plugin"

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# ── 1. Latest release ────────────────────────────────────────────────────────
# Tag format is the bare version (no "v" prefix) — matches the URLs below.
LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/releases/latest" |
  jq -r '.tag_name')
[[ -n $LATEST && $LATEST != "null" ]] || err "Could not fetch latest release"

CURRENT=$(grep -oP "excalidraw-plugin/releases/download/\K[0-9.]+" "$PKG" | head -1)
[[ -n $CURRENT ]] || err "Could not find current pinned version in $PKG"

if [[ $CURRENT == "$LATEST" ]]; then
  log "obsidian-excalidraw-plugin already at $LATEST — nothing to do."
  exit 0
fi
log "Updating $CURRENT → $LATEST"

# ── 2. Bump the version segment in all 3 URLs ────────────────────────────────
sed -i "s#excalidraw-plugin/releases/download/${CURRENT}/#excalidraw-plugin/releases/download/${LATEST}/#g" "$PKG"

# ── 3. Prefetch + patch each asset's hash ────────────────────────────────────
# Set the `sha256 = "..."` that follows this asset's `url = "..."` line, so
# other fetchurls in $PKG can't shift which hash gets patched.
set_hash() {
  local url="$1" value="$2"
  python3 - "$PKG" "$url" "$value" <<'PY'
import sys, re
path, url, value = sys.argv[1:4]
text = open(path).read()
m = re.search(r'url = "' + re.escape(url) + r'";\s*sha256 = "[^"]*"', text)
if not m:
    sys.exit(f"ERROR: no url+sha256 pair for {url} in {path}")
h = re.search(r'sha256 = "[^"]*"', m.group(0))
start, end = m.start() + h.start(), m.start() + h.end()
open(path, 'w').write(text[:start] + f'sha256 = "{value}"' + text[end:])
PY
}

for f in main.js manifest.json styles.css; do
  url="https://github.com/${REPO_SLUG}/releases/download/${LATEST}/${f}"
  log "  hash $f ..."
  hash=$(nix-prefetch-url --type sha256 "$url")
  set_hash "$url" "$hash"
done

log "Done. obsidian-excalidraw-plugin $LATEST ready."
