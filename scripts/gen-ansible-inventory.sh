#!/usr/bin/env nix-shell
#!nix-shell -i bash -p go

set -euo pipefail

# Find inventory.nix relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_NIX="$(realpath "$SCRIPT_DIR/../inventory.nix")"

cd "$SCRIPT_DIR/gen-ansible-inventory"
exec go run main.go "$INVENTORY_NIX"
