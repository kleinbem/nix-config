#!/usr/bin/env bash
# persona-scaffold.sh — provision a single persona end-to-end.
#
# Steps (idempotent — safe to re-run; already-done steps skip):
#   1. Verify the persona is declared in personas.nix.
#   2. Generate ed25519 signing key (under nix-secrets/personas/<name>/).
#   3. Sops-encrypt the private key in place.
#   4. Patch nix-config/modules/nixos/keys.nix ssh.personas.<name> with pubkey.
#   5. Upload the pubkey to GitHub as a Signing key (gh auth required).
#   6. Generate a random mailbox password, store in sops.
#   7. Create the mailbox via Stalwart admin CLI (only if Stalwart is running).
#
# Run AFTER:
#   - nix-config/personas.nix has the entry
#   - Stalwart container is up (for step 7; steps 1-6 work without it)
#   - `gh auth status` shows you're logged in
#
# Usage: just personas::add <name>      (preferred, via the just recipe)
#    or: ./persona-scaffold.sh <name>

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <persona-name>" >&2
  echo "Example: $0 michael" >&2
  exit 1
fi

NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
NIX_CONFIG="$(dirname "$SCRIPT_DIR")"
META_ROOT="$(dirname "$NIX_CONFIG")"
PERSONAS_NIX="$NIX_CONFIG/personas.nix"
KEYS_NIX="$NIX_CONFIG/modules/nixos/keys.nix"
SECRETS_REPO="$META_ROOT/nix-secrets"
PERSONA_SECRETS_DIR="$SECRETS_REPO/personas/$NAME"

# --- 1. Validate persona exists in manifest ---
if ! nix eval --raw --file "$PERSONAS_NIX" --apply "p: if p ? \"$NAME\" then \"ok\" else builtins.throw \"persona $NAME not in personas.nix\"" >/dev/null 2>&1; then
  echo "❌ Persona '$NAME' not declared in $PERSONAS_NIX" >&2
  echo "   Add an attribute block first, then re-run." >&2
  exit 1
fi

PERSONA_EMAIL=$(nix eval --raw --file "$PERSONAS_NIX" --apply "p: p.$NAME.email")
PERSONA_FULLNAME=$(nix eval --raw --file "$PERSONAS_NIX" --apply "p: p.$NAME.\"full-name\"")

echo "🎭 Scaffolding persona: $PERSONA_FULLNAME <$PERSONA_EMAIL>"

# --- 2. Generate signing key (if missing) ---
mkdir -p "$PERSONA_SECRETS_DIR"
KEY_PATH="$PERSONA_SECRETS_DIR/id_ed25519"

if [[ -f "${KEY_PATH}.pub" ]]; then
  echo "  ✓ Signing key already present at $KEY_PATH"
else
  echo "  🔑 Generating ed25519 signing key..."
  ssh-keygen -t ed25519 -C "$PERSONA_EMAIL" -N "" -f "$KEY_PATH" -q
fi

PUBKEY=$(cat "${KEY_PATH}.pub")

# --- 3. Sops-encrypt the private key (if not already encrypted) ---
if [[ -f $KEY_PATH ]] && ! grep -q '"sops":' "$KEY_PATH" 2>/dev/null; then
  if head -1 "$KEY_PATH" | grep -q -- '-----BEGIN'; then
    echo "  🔐 Encrypting private key with sops..."
    (cd "$SECRETS_REPO" && sops --encrypt --in-place "personas/$NAME/id_ed25519")
  fi
fi

# --- 4. Patch keys.nix with the public key ---
if grep -q "\"$NAME\" = \".*\";" "$KEYS_NIX" && ! grep -q "\"$NAME\" = \"\";" "$KEYS_NIX"; then
  echo "  ✓ keys.nix ssh.personas.$NAME already populated"
else
  echo "  📝 Updating keys.nix ssh.personas.$NAME..."
  # Replace the empty placeholder with the actual pubkey.
  sed -i "s|$NAME = \"\";|$NAME = \"$PUBKEY\";|" "$KEYS_NIX"
fi

# --- 5. Upload pubkey to GitHub as a Signing key ---
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  # Check if a key with this title already exists (idempotency)
  EXISTING=$(gh api /user/ssh_signing_keys --jq ".[] | select(.title == \"$PERSONA_EMAIL signing\") | .id" 2>/dev/null || true)
  if [[ -n $EXISTING ]]; then
    echo "  ✓ GitHub already has signing key '$PERSONA_EMAIL signing'"
  else
    echo "  📤 Uploading pubkey to GitHub as signing key..."
    gh api -X POST /user/ssh_signing_keys \
      --field "title=$PERSONA_EMAIL signing" \
      --field "key=$PUBKEY" >/dev/null
  fi
else
  echo "  ⚠️  gh not authenticated — skipping GitHub upload. Run later:"
  echo "     gh api -X POST /user/ssh_signing_keys --field title=\"$PERSONA_EMAIL signing\" --field key=\"$PUBKEY\""
fi

# --- 6. Generate mailbox password (if not already in sops) ---
MAILBOX_PASS_FILE="$PERSONA_SECRETS_DIR/mailbox-password"
if [[ -f $MAILBOX_PASS_FILE ]]; then
  echo "  ✓ Mailbox password already in sops"
else
  echo "  🔐 Generating mailbox password..."
  openssl rand -base64 32 >"$MAILBOX_PASS_FILE"
  (cd "$SECRETS_REPO" && sops --encrypt --in-place "personas/$NAME/mailbox-password")
fi

# --- 7. Create mailbox via Stalwart admin CLI (if Stalwart is running) ---
if systemctl is-active --quiet container@stalwart.service 2>/dev/null; then
  echo "  📬 Creating mailbox in Stalwart..."
  # The mailbox password isn't passed inline (it's set via the API after
  # decryption inside the container); this just ensures the account exists.
  sudo machinectl shell stalwart /run/current-system/sw/bin/stalwart-cli \
    account create "$PERSONA_EMAIL" "$PERSONA_FULLNAME" 2>/dev/null ||
    echo "    (mailbox may already exist — ignore if so)"
else
  echo "  ℹ️  Stalwart not running — mailbox creation deferred."
  echo "     Run after 'just apply' lands the stalwart container:"
  echo "     sudo machinectl shell stalwart stalwart-cli account create '$PERSONA_EMAIL' '$PERSONA_FULLNAME'"
fi

# --- Summary ---
echo
echo "✅ Persona $NAME scaffolded."
echo
echo "Verify with a test commit:"
echo "  just jj::as $NAME save-all \"feat: smoke test as $PERSONA_FULLNAME\""
echo
echo "Remember to commit + push the keys.nix update:"
echo "  just jj::save-all \"chore(keys): register signing key for $PERSONA_FULLNAME\""
