#!/usr/bin/env bash
# Build the dummy nix-secrets tree CI substitutes for the private repo
# (via --override-input nix-secrets). It must mirror every path nix-config
# dereferences at eval/build time — a missing path fails the BUILD with
# "failed to get symlink metadata", even when eval-only checks pass:
#   secrets.yaml                     sops reads (`or`-defaulted in eval)
#   initrd/cryptroot_<host>.jwe      my.boot.clevis-initrd secretFile
#   initrd/ssh_host_ed25519_key_*    rpi5-node + orin-nano initrd SSH host keys
set -euo pipefail

out="${1:-/tmp/dummy-secrets}"
mkdir -p "$out/initrd"
echo "{}" >"$out/secrets.yaml"

for host in nixos-nvme core-pi hass-pi orin-nano; do
  echo "ci-dummy-jwe-placeholder" >"$out/initrd/cryptroot_${host}.jwe"
  # Real key format in case anything parses it at build time.
  if [ ! -f "$out/initrd/ssh_host_ed25519_key_${host}" ]; then
    ssh-keygen -q -t ed25519 -N "" -C "ci-dummy" \
      -f "$out/initrd/ssh_host_ed25519_key_${host}"
  fi
done
