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

# Pull full host and service-node objects directly from inventory.nix.
# We render details (ip/system/tags/domain/description) — name-only lists
# weren't useful enough for AI navigation.
HOSTS_JSON=$(nix eval --json --file "$NIX_CONFIG_ROOT/inventory.nix" hosts)
SERVICES_JSON=$(nix eval --json --file "$NIX_CONFIG_ROOT/inventory.nix" network.nodes)

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
# Format: `- **name** (\`ip\`, system, deployType) — tag, tag, tag`
# Fields may be absent for openwrt/special hosts; jq's // handles defaults.
echo "$HOSTS_JSON" | jq -r '
  to_entries
  | sort_by(.key)
  | .[]
  | "- **\(.key)** "
    + "(`\(.value.ip // "no-ip")`"
    + (if .value.system then ", \(.value.system)" else "" end)
    + (if .value.deployType then ", \(.value.deployType)" else "" end)
    + (if .value.type then ", \(.value.type)" else "" end)
    + ")"
    + (if (.value.tags // []) | length > 0 then " — \(.value.tags | join(", "))" else "" end)
' >>"$OUTPUT_FILE"

echo -e "\n## 📡 Network Services" >>"$OUTPUT_FILE"
# Format: `- icon **Display Name** (\`key\`) — \`ip[:port]\` [→ domain] — description`
echo "$SERVICES_JSON" | jq -r '
  to_entries
  | sort_by(.value.meta.category // "ZZZ", .key)
  | .[]
  | "- "
    + (.value.meta.icon // "📦") + " "
    + "**" + (.value.meta.name // .key) + "**"
    + " (`\(.key)`)"
    + " — `\(.value.ip // "no-ip")"
    + (if .value.port then ":\(.value.port)" else "" end)
    + "`"
    + (if .value.domain then " → `\(.value.domain)`" else "" end)
    + (if .value.meta.description then " — \(.value.meta.description)" else "" end)
' >>"$OUTPUT_FILE"

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
# Parse @mcp.tool() functions properly: name + first-line docstring.
# Previous bash sed pipeline produced `name- ****` because it stripped args
# but never extracted descriptions. Python AST is the right tool here.
python3 - "$META_ROOT/scripts/workspace-mcp.py" >>"$OUTPUT_FILE" <<'PY'
import ast
import sys

source = open(sys.argv[1]).read()
tree = ast.parse(source)

for node in ast.walk(tree):
    if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
    is_tool = any(
        (isinstance(d, ast.Call) and isinstance(d.func, ast.Attribute) and d.func.attr == "tool")
        or (isinstance(d, ast.Attribute) and d.attr == "tool")
        for d in node.decorator_list
    )
    if not is_tool:
        continue
    doc = (ast.get_docstring(node) or "").strip().split("\n")[0].strip().rstrip(".")
    if doc:
        print(f"- **{node.name}** — {doc}.")
    else:
        print(f"- **{node.name}** — _(no docstring)_")
PY

echo "✅ System Reference updated at $OUTPUT_FILE"

# Regenerate the machine-readable my.* options + imports indexes.
if command -v python3 &>/dev/null; then
  python3 "$SCRIPT_DIR/generate-options-index.py" || echo "⚠️  Options index generation failed (non-fatal)"
  python3 "$SCRIPT_DIR/generate-imports-index.py" || echo "⚠️  Imports index generation failed (non-fatal)"
else
  echo "⚠️  python3 not found — skipping AI index regeneration"
fi
