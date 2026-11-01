#!/usr/bin/env bash
# persona-scaffold.sh — provision a single persona end-to-end.
#
# Idempotent: generates the signing key + mailbox password into
# kleinbem-secrets/personas/<name>.yaml, patches keys.nix, uploads the key to
# GitHub as a signing key and creates the Stalwart mailbox if Stalwart runs.
#
# Before: the personas.nix entry, `gh auth status`, and a personas/<name>.yaml
# creation rule in kleinbem-secrets/.sops.yaml (its README "Adding a new scope").
# Without the rule it only warns and the file falls to the masters-only catch-all.
#
# Usage: just personas::add <name>   (or ./persona-scaffold.sh <name>)

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
# kleinbem-secrets holds the signing key + mailbox password, and the plain
# personas/contact.nix (identity data that goes public with the first commit).
SECRETS_REPO="$META_ROOT/kleinbem-secrets"
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

# full-name/email live in kleinbem-secrets/personas/contact.nix (plain Nix,
# imported directly), joined in by lib/personas.nix.
persona_field() {
  nix eval --impure --raw --expr "
    let
      flake = builtins.getFlake (toString \"$NIX_CONFIG\");
      lib = flake.inputs.nixpkgs.lib;
      personas = import \"$NIX_CONFIG/lib/personas.nix\" {
        inherit lib;
        contact = import \"$SECRETS_REPO/personas/contact.nix\";
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
  # Match on key material, not the title: the title embeds the email, so a
  # rename would upload a duplicate. GitHub can't edit a key's title, so a
  # stale one stays (harmless).
  PUBKEY_BLOB=$(awk '{print $2}' <<<"$PUBKEY")
  EXISTING=$(gh api /user/ssh_signing_keys --jq ".[] | select((.key | split(\" \")[1]) == \"$PUBKEY_BLOB\") | .id" 2>/dev/null || true)
  if [[ -n $EXISTING ]]; then
    echo "  ✓ GitHub already has this signing key (id $EXISTING)"
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

# --- 6. Create mailbox via Stalwart's principal API (if Stalwart is running) ---
# Not `stalwart-cli`: it needs /api/schema, which our pinned Stalwart 0.15.5
# lacks (404). Plain `POST /api/principal` instead, curl'd from the mac-mini
# host at the container IP, since the container ships no curl.
STALWART_HOST="mac-mini"
STALWART_IP="10.85.50.8" # inventory.nix network.nodes.stalwart
STALWART_PORT="8080"
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$STALWART_HOST" \
  'systemctl is-active --quiet container@stalwart.service' 2>/dev/null; then
  echo "  📬 Creating mailbox in Stalwart..."
  MAILBOX_LOCALPART="${PERSONA_EMAIL%%@*}"
  MAILBOX_PASSWORD="$(yq '.mailbox_password' "$WORK/persona.yaml")"
  jq -n --arg name "$MAILBOX_LOCALPART" --arg desc "$PERSONA_FULLNAME" \
    --arg email "$PERSONA_EMAIL" --arg secret "$MAILBOX_PASSWORD" '
      {type: "individual", name: $name, description: $desc, quota: 0,
       emails: [$email], secrets: [$secret], roles: ["user"]}
    ' >"$WORK/principal.json"
  # Dedicated `automation` principal, not the human fallback-admin (whose
  # password stays out of sops). Created once by hand: see
  # docs/PHASE1_STALWART_STATUS.md "Automation principal bootstrap".
  AUTOMATION_PASSWORD="$(sops -d --extract '["stalwart_automation_password"]' \
    "$SECRETS_REPO/nix/per-container/stalwart.yaml")"
  if [[ -z $AUTOMATION_PASSWORD ]]; then
    echo "  ⚠️  stalwart_automation_password not in kleinbem-secrets — skipping mailbox creation." >&2
    echo "     See docs/PHASE1_STALWART_STATUS.md 'Automation principal bootstrap' — one-time setup." >&2
  else
    # stderr stays visible: otherwise a connection failure shows only as "000".
    # The password is base64, so it's safe inside these single quotes.
    HTTP_CODE=$(ssh -o BatchMode=yes "$STALWART_HOST" \
      "curl -sS -o /dev/null -w '%{http_code}' \
        -u automation:$AUTOMATION_PASSWORD -H 'Content-Type: application/json' \
        -X POST http://$STALWART_IP:$STALWART_PORT/api/principal --data-binary @-" \
      <"$WORK/principal.json") || HTTP_CODE="000"
    case "$HTTP_CODE" in
    200) echo "    ✓ mailbox created" ;;
    400) echo "    (mailbox may already exist — ignore if so)" ;;
    401) echo "    ⚠️  401 Unauthorized — automation principal password mismatch, re-check the bootstrap" >&2 ;;
    *) echo "    ⚠️  unexpected HTTP $HTTP_CODE creating mailbox" >&2 ;;
    esac
  fi
else
  echo "  ℹ️  Stalwart not running on $STALWART_HOST — mailbox creation deferred."
  echo "     Run after 'just apply' lands the stalwart container (re-run this script)."
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
