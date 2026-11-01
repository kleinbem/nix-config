#!/usr/bin/env bash
# Generates the ground-truth docs for AI assistants in docs/: SYSTEM_REFERENCE.md,
# OPTIONS.md, IMPORTS.md and INFRASTRUCTURE.yaml (one generate-*.py each).
# Paths resolve from the script's location. --no-ci skips the gh calls
# (faster, but no CI Status section).

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NIX_CONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
META_ROOT="$(dirname "$NIX_CONFIG_ROOT")"

# Pinned interpreter (nix-config#legacyPackages.<system>.agent-python) so the
# generators' deps (pyyaml) don't hinge on whichever python3 is first on PATH.
# Falls back to the ambient python3 if the build fails (e.g. offline).
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem 2>/dev/null || echo x86_64-linux)"
# NIX_OVERRIDES: extra flags, e.g. CI's --override-input kleinbem-secrets <dummy>.
# shellcheck disable=SC2086
if PY_ENV="$(nix build --no-link --print-out-paths "$NIX_CONFIG_ROOT#legacyPackages.$SYSTEM.agent-python" ${NIX_OVERRIDES:-} 2>/dev/null)"; then
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
