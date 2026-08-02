#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <host>"
  echo "Example: $0 core-pi"
  exit 1
fi

HOST="$1"
HOST_DIR="hosts/$HOST"
# This must match what `my.boot.clevis-initrd.secretFile` actually reads
# (see modules/nixos/clevis-initrd.nix consumers, e.g. hosts/*/services.nix
# or hosts/*/default.nix: "${inputs.nix-secrets}/initrd/cryptroot_${HOST}.jwe").
# Previously wrote to hosts/$HOST/cryptroot.jwe, a path nothing reads — every
# real cryptroot_*.jwe in nix-secrets/initrd/ was produced some other way.
SECRETS_DIR="../nix-secrets/initrd"
JWE_FILE="$SECRETS_DIR/cryptroot_${HOST}.jwe"

if [ ! -d "$HOST_DIR" ]; then
  echo "Error: Host directory $HOST_DIR does not exist."
  exit 1
fi

if [ ! -d "$SECRETS_DIR" ]; then
  echo "Error: $SECRETS_DIR does not exist (run from the nix-config repo root, with nix-secrets cloned as a sibling)."
  exit 1
fi

echo "🔑 Generating new cryptroot.jwe for $HOST using 3-server Tang cluster..."
echo "Servers: nixos-nvme (10.0.0.5), hass-pi (10.0.0.21), orin-nano (10.0.0.15)"

read -r -s -p "Enter LUKS passphrase for $HOST: " PASSPHRASE
echo ""

echo -n "$PASSPHRASE" | clevis encrypt sss '{"t": 1, "pins": {"tang": [{"url": "http://10.0.0.5:7654", "adv": "hosts/nixos-nvme/tang-adv.jws"}, {"url": "http://10.0.0.21:7654", "adv": "hosts/hass-pi/tang-adv.jws"}, {"url": "http://10.0.0.15:7654", "adv": "hosts/orin-nano/tang-adv.jws"}]}}' >"$JWE_FILE.new"

mv "$JWE_FILE.new" "$JWE_FILE"
echo "✅ Successfully updated $JWE_FILE"
echo "Next step: run 'nixos-rebuild switch' or your deployment recipe to push the new JWE to the host's initrd."
