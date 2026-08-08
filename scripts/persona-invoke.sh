#!/usr/bin/env bash
# persona-invoke.sh — run a persona through the shared persona-runtime
# container: writes that persona's real identity into the fixed host
# paths nix-presets/containers/persona-runtime.nix bind-mounts, starts
# the container fresh, runs the persona's tool, tears down.
#
# Architecture: see persona-runtime.nix's header comment. One container,
# shared across every persona, identity swapped per invocation instead
# of one standing container per persona — the model that actually scales
# to "many personas, never running concurrently."
#
# MUST run as root: machinectl start/stop plus writing the root:root
# identity files persona-runtime.nix's systemd.tmpfiles.rules creates.
#
# Only hermes-agent is wired into the shared runtime image so far (see
# persona-runtime.nix's environment.systemPackages = [ ] comment) — a
# persona whose declared `tool` is claude-code/aider/antigravity/
# self-hosted-runner will fail cleanly with a note about what's missing,
# not silently run the wrong thing.
#
# Model is NOT auto-derived from personas.nix's declared `model` field —
# juan's declared gemini-2.5-pro doesn't actually work on the free tier
# (confirmed live 2026-08-08; gemini-flash-latest does). Pass -m
# yourself if the persona's tool needs it; don't assume the declared
# model is what actually works.
#
# Usage:
#   sudo ./persona-invoke.sh juan -m gemini/gemini-flash-latest -z "What's 2+2?"
#   sudo ./persona-invoke.sh juan                                    # interactive
#   sudo ./persona-invoke.sh michael -z "..."                        # any provisioned persona

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ Must run as root — machinectl start/stop, and writes root:root identity files." >&2
  echo "   sudo $0 $*" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <persona-name> [-- extra args passed straight to the tool]" >&2
  exit 1
fi

NAME="$1"
shift
TOOL_ARGS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
NIX_CONFIG="$(dirname "$SCRIPT_DIR")"
META_ROOT="$(dirname "$NIX_CONFIG")"
SECRETS_ROOT="${KLEINBEM_SECRETS_ROOT:-$META_ROOT/kleinbem-secrets}"
PERSONAS_NIX="$NIX_CONFIG/personas.nix"
PERSONA_YAML="$SECRETS_ROOT/personas/$NAME.yaml"
CONTACT_ENCRYPTED="$SECRETS_ROOT/personas/contact.nix"
RUNTIME_DIR=/var/lib/persona-runtime
DATA_DIR=/var/lib/persona-runtime-data

if [[ ! -d $SECRETS_ROOT ]]; then
  echo "❌ kleinbem-secrets not found at $SECRETS_ROOT." >&2
  echo "   Clone it there, or set KLEINBEM_SECRETS_ROOT." >&2
  exit 1
fi

if [[ ! -f $PERSONA_YAML ]]; then
  echo "❌ No secrets file for persona '$NAME' at $PERSONA_YAML." >&2
  exit 1
fi

if ! nix eval --raw --file "$PERSONAS_NIX" --apply "p: if p ? \"$NAME\" then \"ok\" else builtins.throw \"missing\"" >/dev/null 2>&1; then
  echo "❌ Persona '$NAME' not declared in $PERSONAS_NIX." >&2
  exit 1
fi

TOOL=$(nix eval --raw --file "$PERSONAS_NIX" --apply "p: p.$NAME.tool")
echo "🎭 Invoking $NAME (tool: $TOOL)"

if [[ $TOOL != "gemini-cli" ]]; then
  echo "⚠️  '$TOOL' isn't wired into the shared persona-runtime image yet (only hermes-agent / gemini-cli-style personas are)." >&2
  echo "   Add it to nix-presets/containers/persona-runtime.nix's environment.systemPackages first." >&2
  exit 1
fi

WORK="$(mktemp -d /dev/shm/persona-invoke-XXXXXX)"
trap 'find "$WORK" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "$WORK"' EXIT

echo "🔓 Decrypting $NAME's identity..."
sops -d --input-type binary --output-type binary "$CONTACT_ENCRYPTED" >"$WORK/contact.nix"

FULLNAME=$(CONTACT_PATH="$WORK/contact.nix" nix eval --raw --impure --expr "
  let
    lib = (import <nixpkgs> {}).lib;
    contactPath = builtins.getEnv \"CONTACT_PATH\";
    contact = import contactPath;
    p = import $NIX_CONFIG/lib/personas.nix { inherit lib contact; };
  in p.all.$NAME.\"full-name\"
")
EMAIL=$(CONTACT_PATH="$WORK/contact.nix" nix eval --raw --impure --expr "
  let
    lib = (import <nixpkgs> {}).lib;
    contactPath = builtins.getEnv \"CONTACT_PATH\";
    contact = import contactPath;
    p = import $NIX_CONFIG/lib/personas.nix { inherit lib contact; };
  in p.all.$NAME.email
")

SIGNING_KEY=$(sops -d --extract '["id_ed25519"]' "$PERSONA_YAML" 2>/dev/null || echo "")
if [[ -z $SIGNING_KEY ]]; then
  echo "❌ No id_ed25519 field in $PERSONA_YAML." >&2
  exit 1
fi
API_KEY=$(sops -d --extract '["gemini_api_key"]' "$PERSONA_YAML" 2>/dev/null || echo "")

echo "✍️  Writing identity into $RUNTIME_DIR (fixed paths, root:root)..."
umask 077
printf '%s' "$SIGNING_KEY" >"$RUNTIME_DIR/signing-key"
chmod 600 "$RUNTIME_DIR/signing-key"

cat >"$RUNTIME_DIR/gitconfig" <<EOF
[user]
	name = $FULLNAME
	email = $EMAIL
	signingkey = /run/secrets/signing-key
[commit]
	gpgsign = true
[gpg]
	format = ssh
EOF
chmod 644 "$RUNTIME_DIR/gitconfig"

if [[ -n $API_KEY ]]; then
  printf 'GEMINI_API_KEY=%s\n' "$API_KEY" >"$RUNTIME_DIR/agent.env"
else
  : >"$RUNTIME_DIR/agent.env"
fi
chmod 600 "$RUNTIME_DIR/agent.env"

# Clean slate — see mac-mini/default.nix's persona-runtime comment on why
# this isn't in the persistence list: a host-side bind mount survives the
# container's own ephemeral rootfs reset, so without this, one persona's
# session state would bleed into the next persona's context.
echo "🧹 Clearing previous session state..."
rm -rf "${DATA_DIR:?}"/*

echo "🚀 Starting persona-runtime as $NAME..."
machinectl start persona-runtime

for _ in $(seq 1 20); do
  if machinectl show persona-runtime -p State 2>/dev/null | grep -q '^State=running'; then
    break
  fi
  sleep 0.5
done

set +e
machinectl shell \
  --setenv=HOME=/var/lib/hermes \
  --setenv=HERMES_HOME=/var/lib/hermes/.hermes \
  persona-runtime /run/current-system/sw/bin/hermes "${TOOL_ARGS[@]}"
RESULT=$?
set -e

echo "🛑 Stopping persona-runtime..."
machinectl poweroff persona-runtime 2>/dev/null || true

exit "$RESULT"
