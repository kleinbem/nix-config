#!/usr/bin/env bash
# Print the clevis sss config for <host>: all other hosts' Tang servers,
# pinned by thumbprint (inventory.nix `tang`, lib/tang.nix). Run from the
# nix-config root.
set -euo pipefail
host="${1:?usage: tang-config.sh <host>}"
nix eval --raw --impure --expr "builtins.toJSON ((import ./lib/tang.nix).binding \"$host\")"
