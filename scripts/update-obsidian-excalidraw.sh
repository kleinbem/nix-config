#!/usr/bin/env bash
# Update the pinned Obsidian Excalidraw plugin (zsviczian/obsidian-excalidraw-
# plugin) in users/martin/home.nix to the latest GitHub release.
#
# Upstream publishes the plugin as 3 plain release assets (main.js,
# manifest.json, styles.css), each pinned via a separate pkgs.fetchurl. There
# is no build logic beyond the fetch itself, so nix-prefetch-url downloading
# + hashing each file IS the verification — no separate Nix build needed.
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
# Replace the Nth occurrence (1-indexed) of `sha256 = "..."` in $PKG.
set_hash() {
  local n="$1" value="$2"
  python3 - "$PKG" "$n" "$value" <<'PY'
import sys, re
path, n, value = sys.argv[1], int(sys.argv[2]), sys.argv[3]
text = open(path).read()
pattern = r'sha256 = "[^"]*"'
matches = list(re.finditer(pattern, text))
if len(matches) < n:
    print(f"ERROR: only {len(matches)} sha256= lines found, wanted index {n}", file=sys.stderr)
    sys.exit(1)
m = matches[n - 1]
open(path, 'w').write(text[:m.start()] + f'sha256 = "{value}"' + text[m.end():])
PY
}

# Order must match the 3 fetchurl blocks' appearance in $PKG (main.js,
# manifest.json, styles.css) — same order they're written in home.nix.
FILES=(main.js manifest.json styles.css)
for i in "${!FILES[@]}"; do
  f="${FILES[$i]}"
  url="https://github.com/${REPO_SLUG}/releases/download/${LATEST}/${f}"
  log "  hash $f ..."
  hash=$(nix-prefetch-url --type sha256 "$url")
  set_hash "$((i + 1))" "$hash"
done

log "Done. obsidian-excalidraw-plugin $LATEST ready."
