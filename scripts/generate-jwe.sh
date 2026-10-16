#!/usr/bin/env bash
# (Re)generate kleinbem-secrets/initrd/cryptroot_<host>.jwe, the Tang-wrapped
# LUKS passphrase that my.boot.clevis-initrd.secretFile unlocks at boot.
#
# The binding comes from inventory.nix via scripts/tang-config.sh: every OTHER
# host's Tang server, t = 1, each pinned by thumbprint.
#
# If the current JWE still decrypts (any of its Tang servers reachable), its
# content is re-wrapped as is: no LUKS change and no prompt. The passphrase
# only travels through pipes, and the new JWE is decrypted again and compared
# by hash before it replaces the old one. Otherwise the passphrase is taken
# from $LUKS_PASSPHRASE or prompted, as before.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <host>" >&2
  exit 1
fi
HOST="$1"
SECRETS_DIR="${KLEINBEM_SECRETS:-../kleinbem-secrets}/initrd"
JWE_FILE="$SECRETS_DIR/cryptroot_${HOST}.jwe"

[ -d "hosts/$HOST" ] || {
  echo "Error: hosts/$HOST does not exist." >&2
  exit 1
}
[ -d "$SECRETS_DIR" ] || {
  echo "Error: $SECRETS_DIR missing (run from nix-config with kleinbem-secrets cloned as a sibling)." >&2
  exit 1
}

CFG=$(bash scripts/tang-config.sh "$HOST")
echo "🔑 $HOST → Tang: $(echo "$CFG" | jq -r '[.pins.tang[].url | sub("http://"; "")] | join(", ")')"

tmp="$JWE_FILE.new"
trap 'rm -f "$tmp"' EXIT

if [ -f "$JWE_FILE" ] && old_hash=$(clevis decrypt <"$JWE_FILE" 2>/dev/null | sha256sum) &&
  [ "$old_hash" != "$(printf '' | sha256sum)" ]; then
  echo "   Re-wrapping the current JWE content (no prompt, LUKS unchanged)."
  clevis decrypt <"$JWE_FILE" | clevis encrypt sss "$CFG" -y >"$tmp"
  expected="$old_hash"
else
  if [ -n "${LUKS_PASSPHRASE:-}" ]; then
    PASSPHRASE="$LUKS_PASSPHRASE"
  else
    read -r -s -p "Enter LUKS passphrase for $HOST: " PASSPHRASE
    echo ""
  fi
  printf '%s' "$PASSPHRASE" | clevis encrypt sss "$CFG" -y >"$tmp"
  expected=$(printf '%s' "$PASSPHRASE" | sha256sum)
  unset PASSPHRASE
fi

if [ "$(clevis decrypt <"$tmp" | sha256sum)" != "$expected" ]; then
  echo "❌ New JWE does not decrypt to the same content; $JWE_FILE left unchanged." >&2
  exit 1
fi
mv "$tmp" "$JWE_FILE"
trap - EXIT
echo "✅ $JWE_FILE updated and verified. Commit it in kleinbem-secrets, bump the lock in nix-config, deploy $HOST."
