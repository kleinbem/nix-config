#!/usr/bin/env bash
# SOURCE OF TRUTH: nix-config/scripts/tag-generation.sh

# Get the current system generation number
GEN=$(readlink /nix/var/nix/profiles/system | grep -oP "system-\K[0-9]+")

if [ -z "$GEN" ]; then
  echo "❌ Could not determine NixOS generation."
  exit 1
fi

TAG="gen-$GEN"

# Check if target is a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "⚠️ Not a git repository. Skipping tag."
  exit 0
fi

# Check for any uncommitted changes (staged or unstaged)
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️ SKIPPING TAG: You have uncommitted changes. To map this generation to your source, please COMMIT your changes and run 'just switch' again."
  exit 0
fi

# Create the tag
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "ℹ️ Tag $TAG already exists. Moving it to current commit."
  git tag -f "$TAG"
else
  echo "✅ Tagging current commit as $TAG"
  git tag "$TAG"
fi

# Optional: Add a note or push if configured
# git push origin "$TAG" --force
