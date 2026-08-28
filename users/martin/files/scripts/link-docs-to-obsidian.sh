#!/usr/bin/env bash
set -e

# Documentation Linker for Obsidian
# Purpose: Symlink every fleet repo's `.agent/` directory (lessons,
# architecture notes, rules, CONTEXT/handover, knowledge/) into the
# Obsidian vault for browsing. Always a symlink, never a copy — each repo
# stays the source of truth and stays git-versioned; the vault just gets a
# read-only window into it.

VAULT_PATH="$HOME/Documents/Notes"
KNOWLEDGE_ROOT="$VAULT_PATH/System/Knowledge"
# The flat workspace root (~15 sibling repos), not any one repo inside it —
# see the workspace CLAUDE.md. Previously this pointed at the `nix` repo
# itself, so the sibling-repo glob below searched inside `nix/` and never
# found anything; only `nix/.agent/knowledge` (as "Main") ever got linked.
WORKSPACE_ROOT="$HOME/Develop/github.com/kleinbem"

mkdir -p "$KNOWLEDGE_ROOT"

echo "🔗 Linking fleet repo knowledge to Obsidian..."

# Drop the old special-cased "Main" symlink from the pre-fix layout — every
# repo (including `nix`) is now linked under its own name below.
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
