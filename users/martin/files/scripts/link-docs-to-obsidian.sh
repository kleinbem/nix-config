#!/usr/bin/env bash
set -e

# Symlink every fleet repo's `.agent/` directory into the Obsidian vault.
# Symlinks, never copies, so each repo stays the source of truth.

VAULT_PATH="$HOME/Documents/Notes"
KNOWLEDGE_ROOT="$VAULT_PATH/System/Knowledge"
# The flat workspace root holding the sibling repos, not any one repo.
WORKSPACE_ROOT="$HOME/Develop/github.com/kleinbem"

mkdir -p "$KNOWLEDGE_ROOT"

echo "🔗 Linking fleet repo knowledge to Obsidian..."

# Drop the legacy "Main" link; every repo is linked under its own name.
rm -f "$KNOWLEDGE_ROOT/Main"

for repo in "$WORKSPACE_ROOT"/*/; do
  repo="${repo%/}"
  repo_name=$(basename "$repo")
  [ -d "$repo/.git" ] || continue
  case "$repo_name" in
  *secrets*)
    # Never symlink *-secrets repos, even just their .agent/ metadata —
    # not worth the risk of a plaintext slip surfacing in the vault.
    continue
    ;;
  esac
  if [ -d "$repo/.agent" ]; then
    echo "  - Linking $repo_name..."
    ln -sfn "$repo/.agent" "$KNOWLEDGE_ROOT/$repo_name"
  fi
done

# Clean up dangling symlinks left behind by repos that were removed or no
# longer have a .agent/ directory.
find "$KNOWLEDGE_ROOT" -maxdepth 1 -xtype l -delete

echo "✅ Documentation linked to $KNOWLEDGE_ROOT"
