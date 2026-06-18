#!/usr/bin/env bash
# sync-agent-context.sh — Generates ground-truth docs for AI assistants.
#
# Outputs:
#   <nix-config>/docs/SYSTEM_REFERENCE.md  (via generate-system-reference.py)
#   <nix-config>/docs/OPTIONS.md           (via generate-options-index.py)
#   <nix-config>/docs/IMPORTS.md           (via generate-imports-index.py)
#
# Lives at nix-config/scripts/; resolves both NIX_CONFIG_ROOT and the parent
# meta-workspace from the script's own location so it doesn't depend on the
# invocation directory.
#
# Speed: pass --no-ci to skip the gh CLI roundtrips (saves ~6s but loses the
# CI Status section).

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NIX_CONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
META_ROOT="$(dirname "$NIX_CONFIG_ROOT")"

echo "🔍 Generating System Reference for AI assistants…"
python3 "$SCRIPT_DIR/generate-system-reference.py" \
  --nix-config "$NIX_CONFIG_ROOT" \
  --meta "$META_ROOT" \
  "$@"

# Regenerate the machine-readable my.* options + imports indexes.
if command -v python3 &>/dev/null; then
  python3 "$SCRIPT_DIR/generate-options-index.py" || echo "⚠️  Options index generation failed (non-fatal)"
  python3 "$SCRIPT_DIR/generate-imports-index.py" || echo "⚠️  Imports index generation failed (non-fatal)"
else
  echo "⚠️  python3 not found — skipping AI index regeneration"
fi
