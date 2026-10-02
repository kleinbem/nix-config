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

# Pinned interpreter (nix-config#legacyPackages.<system>.agent-python) so the
# generators' deps (pyyaml) don't hinge on whichever python3 is first on PATH.
# Falls back to the ambient python3 if the build fails (e.g. offline).
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem 2>/dev/null || echo x86_64-linux)"
if PY_ENV="$(nix build --no-link --print-out-paths "$NIX_CONFIG_ROOT#legacyPackages.$SYSTEM.agent-python" 2>/dev/null)"; then
  PYTHON="$PY_ENV/bin/python3"
else
  echo "⚠️  Couldn't build pinned agent-python — falling back to ambient python3"
  PYTHON="$(command -v python3 || true)"
fi

echo "🔍 Generating System Reference for AI assistants…"
"$PYTHON" "$SCRIPT_DIR/generate-system-reference.py" \
  --nix-config "$NIX_CONFIG_ROOT" \
  --meta "$META_ROOT" \
  "$@"

# Regenerate the machine-readable my.* options + imports indexes + AI infrastructure manifest.
if [ -n "$PYTHON" ]; then
  "$PYTHON" "$SCRIPT_DIR/generate-options-index.py" || echo "⚠️  Options index generation failed (non-fatal)"
  "$PYTHON" "$SCRIPT_DIR/generate-imports-index.py" || echo "⚠️  Imports index generation failed (non-fatal)"
  "$PYTHON" "$SCRIPT_DIR/generate-infra-yaml.py" || echo "⚠️  Infrastructure YAML generation failed (non-fatal)"
else
  echo "⚠️  python3 not found — skipping AI index regeneration"
fi
