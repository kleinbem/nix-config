#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <host>"
    echo "Example: $0 core-pi"
    exit 1
fi

HOST="$1"
HOST_DIR="hosts/$HOST"
JWE_FILE="$HOST_DIR/cryptroot.jwe"

if [ ! -d "$HOST_DIR" ]; then
    echo "Error: Host directory $HOST_DIR does not exist."
    exit 1
fi

echo "🔑 Generating new cryptroot.jwe for $HOST using 3-server Tang cluster..."
echo "Servers: nixos-nvme (10.0.0.5), hass-pi (10.0.0.21), orin-nano (10.0.0.12)"

read -s -p "Enter LUKS passphrase for $HOST: " PASSPHRASE
echo ""

echo -n "$PASSPHRASE" | clevis encrypt sss '{"t": 1, "pins": {"tang": [{"url": "http://10.0.0.5:7654", "adv": "hosts/nixos-nvme/tang-adv.jws"}, {"url": "http://10.0.0.21:7654", "adv": "hosts/hass-pi/tang-adv.jws"}, {"url": "http://10.0.0.12:7654", "adv": "hosts/orin-nano/tang-adv.jws"}]}}' > "$JWE_FILE.new"

mv "$JWE_FILE.new" "$JWE_FILE"
echo "✅ Successfully updated $JWE_FILE"
echo "Next step: run 'nixos-rebuild switch' or your deployment recipe to push the new JWE to the host's initrd."
