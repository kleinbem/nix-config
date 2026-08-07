#!/usr/bin/env bash
# persona-scaffold.sh — provision a single persona end-to-end.
#
# Steps (idempotent — safe to re-run; already-done steps skip):
#   1. Verify the persona is declared in personas.nix.
#   2. Generate ed25519 signing key + mailbox password (tmpfs-staged), merge
#      into kleinbem-secrets/personas/<name>.yaml (id_ed25519, id_ed25519_pub,
#      mailbox_password keys — one YAML per persona, cutover 2026-08-07).
#   3. Patch nix-config/modules/nixos/keys.nix ssh.personas.<name> with pubkey.
#   4. Upload the pubkey to GitHub as a Signing key (gh auth required).
#   5. Create the mailbox via Stalwart admin CLI (only if Stalwart is running).
#
# Run AFTER:
#   - nix-config/personas.nix has the entry
#   - kleinbem-secrets/.sops.yaml has a &persona_<name> anchor + a
#     personas/<name>.yaml creation rule (see that repo's README "Adding a
#     new scope" section) — this script WARNS but does not fail if missing;
#     without it the new content still encrypts, just to the generic
#     personas/.+ catch-all (masters-only, no nixos_nvme/mac_mini access).
#   - Stalwart container is up (for step 5; steps 1-4 work without it)
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
# kleinbem-secrets holds signing key + mailbox password (cutover 2026-08-07).
# personas-contact.nix (PII) is a DELIBERATE, TRACKED EXCEPTION that stays on
# the old nix-secrets repo for now — see nix-config/flake.nix's
# nix-secrets-legacy-contact input and hosts/mac-mini/secrets.nix's comment.
SECRETS_REPO="$META_ROOT/kleinbem-secrets"
CONTACT_REPO="$META_ROOT/nix-secrets"
PERSONA_YAML="$SECRETS_REPO/personas/$NAME.yaml"

WORK="$(mktemp -d /dev/shm/persona-scaffold-XXXXXX)"
cleanup() {
  find "$WORK" -type f -exec shred -u {} \; 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- 1. Validate persona exists in manifest ---
if ! nix eval --raw --file "$PERSONAS_NIX" --apply "p: if p ? \"$NAME\" then \"ok\" else builtins.throw \"persona $NAME not in personas.nix\"" >/dev/null 2>&1; then
  echo "❌ Persona '$NAME' not declared in $PERSONAS_NIX" >&2
  echo "   Add an attribute block first, then re-run." >&2
  exit 1
fi

if ! grep -q "&persona_${NAME}\b" "$SECRETS_REPO/.sops.yaml" 2>/dev/null; then
  echo "⚠️  No '&persona_${NAME}' anchor in kleinbem-secrets/.sops.yaml — this" >&2
  echo "   persona's content will encrypt to the generic personas/.+ catch-all" >&2
  echo "   (masters-only), NOT to nixos_nvme/mac_mini. See kleinbem-secrets/" >&2
  echo "   README.md's 'Adding a new scope' section to onboard it properly first." >&2
fi

# email/full-name are PII — they live in nix-secrets/personas-contact.nix,
# not the public personas.nix, and are only available via lib/personas.nix's
# joined view (see that file's header comment).
persona_field() {
  nix eval --impure --raw --expr "
    let
      flake = builtins.getFlake (toString \"$NIX_CONFIG\");
      lib = flake.inputs.nixpkgs.lib;
      personas = import \"$NIX_CONFIG/lib/personas.nix\" {
        inherit lib;
        contact = import \"$CONTACT_REPO/personas-contact.nix\";
      };
    in personas.all.$NAME.$1
  "
}
PERSONA_EMAIL=$(persona_field email)
PERSONA_FULLNAME=$(persona_field '"full-name"')

echo "🎭 Scaffolding persona: $PERSONA_FULLNAME <$PERSONA_EMAIL>"

# Decrypt the persona's existing kleinbem-secrets content (if any) once, so
# steps 2/3 below can check what's already present and merge into the same
# plaintext staging file before a single re-encrypt at the end.
if [[ -f $PERSONA_YAML ]]; then
  sops -d "$PERSONA_YAML" >"$WORK/persona.yaml"
else
  echo "{}" >"$WORK/persona.yaml"
fi
CHANGED=0

# --- 2. Generate signing key (if missing) ---
if yq -e '.id_ed25519_pub' "$WORK/persona.yaml" >/dev/null 2>&1; then
  echo "  ✓ Signing key already present in $PERSONA_YAML"
  PUBKEY="$(yq '.id_ed25519_pub' "$WORK/persona.yaml")"
else
  echo "  🔑 Generating ed25519 signing key..."
  ssh-keygen -t ed25519 -C "$PERSONA_EMAIL" -N "" -f "$WORK/id_ed25519" -q
  PUBKEY="$(cat "$WORK/id_ed25519.pub")"
  ID_PATH="$WORK/id_ed25519" PUB_PATH="$WORK/id_ed25519.pub" \
    yq -i '.id_ed25519 = load_str(strenv(ID_PATH)) | .id_ed25519_pub = load_str(strenv(PUB_PATH))' \
    "$WORK/persona.yaml"
  CHANGED=1
fi

# --- 3. Generate mailbox password (if missing) ---
if yq -e '.mailbox_password' "$WORK/persona.yaml" >/dev/null 2>&1; then
  echo "  ✓ Mailbox password already present in $PERSONA_YAML"
else
  echo "  🔐 Generating mailbox password..."
  openssl rand -base64 32 >"$WORK/mailbox-password"
  MB_PATH="$WORK/mailbox-password" \
    yq -i '.mailbox_password = load_str(strenv(MB_PATH))' "$WORK/persona.yaml"
  CHANGED=1
fi

if [[ $CHANGED -eq 1 ]]; then
  echo "  🔐 Encrypting $PERSONA_YAML..."
  mkdir -p "$(dirname "$PERSONA_YAML")"
  sops --config "$SECRETS_REPO/.sops.yaml" --filename-override "$PERSONA_YAML" \
    -e "$WORK/persona.yaml" >"$WORK/persona-enc.yaml"
  mv "$WORK/persona-enc.yaml" "$PERSONA_YAML"
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

# --- 6. Create mailbox via Stalwart admin CLI (if Stalwart is running) ---
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
echo "Remember to commit + push the keys.nix update and kleinbem-secrets:"
echo "  just jj::save-all \"chore(keys): register signing key for $PERSONA_FULLNAME\" nix-config kleinbem-secrets"
