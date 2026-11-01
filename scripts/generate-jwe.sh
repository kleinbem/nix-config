#!/usr/bin/env bash
# (Re)generate kleinbem-secrets/initrd/cryptroot_<host>.jwe, the Tang-wrapped
# LUKS passphrase that my.boot.clevis-initrd.secretFile unlocks at boot.
#
# Binding from scripts/tang-config.sh: every other host's Tang, t = 1, pinned.
# If the current JWE still decrypts, its content is re-wrapped without a prompt
# and verified by hash before replacing the old one. Otherwise (or with
# --new-passphrase) the passphrase comes from $LUKS_PASSPHRASE or a prompt and,
# on the local host, is tested against the LUKS device first.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != "--new-passphrase" ]; }; then
  echo "Usage: $0 <host> [--new-passphrase]" >&2
  exit 1
fi
HOST="$1"
NEW_PASSPHRASE="${2:-}"
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

if [ -z "$NEW_PASSPHRASE" ] && [ -f "$JWE_FILE" ] && old_hash=$(clevis decrypt <"$JWE_FILE" 2>/dev/null | sha256sum) &&
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
  if [ "$HOST" = "$(hostname)" ]; then
    crypt=$(nix eval --raw ".#nixosConfigurations.$HOST.config.my.boot.clevis-initrd.luksDevice")
    dev=$(sudo cryptsetup status "$crypt" | sed -n 's/^ *device: *//p')
    if ! printf '%s' "$PASSPHRASE" | sudo cryptsetup open --test-passphrase --key-file - "$dev"; then
      echo "❌ That passphrase does not open $dev; $JWE_FILE left unchanged." >&2
      exit 1
    fi
    echo "   Passphrase opens $dev."
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
