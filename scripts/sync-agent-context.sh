#!/usr/bin/env bash
# sync-agent-context.sh — Generates ground-truth docs for AI assistants.
#
# Outputs:
#   <nix-config>/docs/SYSTEM_REFERENCE.md  (hand-rendered below)
#   <nix-config>/docs/OPTIONS.md           (via generate-options-index.py)
#   <nix-config>/docs/IMPORTS.md           (via generate-imports-index.py)
#
# Lives at nix-config/scripts/; resolves both NIX_CONFIG_ROOT and the parent
# meta-workspace from the script's own location so it doesn't depend on the
# invocation directory.

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NIX_CONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
META_ROOT="$(dirname "$NIX_CONFIG_ROOT")"
OUTPUT_FILE="$NIX_CONFIG_ROOT/docs/SYSTEM_REFERENCE.md"

echo "🔍 Generating System Reference for Antigravity..."

# Pull host list and service node names directly from inventory.nix.
HOSTS=$(nix eval --json --file "$NIX_CONFIG_ROOT/inventory.nix" hosts --apply "builtins.attrNames" | jq -r '.[]')
SERVICES=$(nix eval --json --file "$NIX_CONFIG_ROOT/inventory.nix" network.nodes --apply "builtins.attrNames" | jq -r '.[]')

cat <<EOF >"$OUTPUT_FILE"
# 🏗️ System Reference (Auto-generated)
*Last Updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")*

> [!IMPORTANT]
> This file contains the "ground truth" for the current NixOS infrastructure.
> Antigravity MUST read this file at the start of any configuration task.

## 📦 Core Revisions
EOF

# Extract nixpkgs revision from the meta-workspace lockfile — that's the lock
# the deployed system uses (`nh os switch .` runs from meta root).
NIXPKGS_REV=$(grep -A 10 '"nixpkgs":' "$META_ROOT/flake.lock" | grep '"rev":' | head -n 1 | awk -F'"' '{print $4}')
echo "- **nixpkgs**: [\`$NIXPKGS_REV\`](https://github.com/NixOS/nixpkgs/commit/$NIXPKGS_REV)" >>"$OUTPUT_FILE"

inputs=("home-manager" "devenv" "sops-nix" "nix-config" "nix-packages" "nix-hardware")
for input in "${inputs[@]}"; do
  REV=$(grep -A 10 "\"$input\":" "$META_ROOT/flake.lock" | grep '"rev":' | head -n 1 | awk -F'"' '{print $4}')
  if [ -n "$REV" ]; then
    echo "- **$input**: \`$REV\`" >>"$OUTPUT_FILE"
  fi
done

echo -e "\n## 🖥️ Managed Hosts" >>"$OUTPUT_FILE"
for host in $HOSTS; do
  echo "- **$host**" >>"$OUTPUT_FILE"
done

echo -e "\n## 📡 Network Services" >>"$OUTPUT_FILE"
for svc in $SERVICES; do
  echo "- **$svc**" >>"$OUTPUT_FILE"
done

echo -e "\n## 🛠️ Workspace Status" >>"$OUTPUT_FILE"
if command -v devenv &>/dev/null; then
  echo "- **Devenv**: Available" >>"$OUTPUT_FILE"
else
  echo "- **Devenv**: Not found in path" >>"$OUTPUT_FILE"
fi

if systemctl --user is-active workspace-guardian.service &>/dev/null; then
  echo "- **Autonomous Guardian**: Active ✅" >>"$OUTPUT_FILE"
else
  echo "- **Autonomous Guardian**: Inactive ❌" >>"$OUTPUT_FILE"
fi

echo -e "\n## 🤖 AI Capabilities (MCP Tools)" >>"$OUTPUT_FILE"
# workspace-mcp.py lives at the meta root (MCP is a meta-workspace concern).
grep "@mcp.tool()" -A 1 "$META_ROOT/scripts/workspace-mcp.py" | grep "def " | sed 's/def //; s/(.*):/- **/; s/$/\**/' >>"$OUTPUT_FILE"

echo "✅ System Reference updated at $OUTPUT_FILE"

# Regenerate the machine-readable my.* options + imports indexes.
if command -v python3 &>/dev/null; then
  python3 "$SCRIPT_DIR/generate-options-index.py" || echo "⚠️  Options index generation failed (non-fatal)"
  python3 "$SCRIPT_DIR/generate-imports-index.py" || echo "⚠️  Imports index generation failed (non-fatal)"
else
  echo "⚠️  python3 not found — skipping AI index regeneration"
fi
