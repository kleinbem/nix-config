#!/usr/bin/env bash
# Build the dummy kleinbem-secrets tree CI substitutes for the private repo
# (via --override-input nix-secrets — identifier kept as "nix-secrets" for
# historical reasons, see flake.nix's note; underlying repo is
# kleinbem-secrets since the 2026-08-07 cutover). It must mirror every path
# nix-config dereferences at eval/build time — a missing path fails the
# BUILD with "failed to get symlink metadata", even when eval-only checks
# pass:
#   nix/shared.yaml                  defaultSopsFile on every host
#   nix/per-host/<host>.yaml         per-host sopsFile overrides
#   initrd/cryptroot_<host>.jwe      my.boot.clevis-initrd secretFile
#   initrd/ssh_host_ed25519_key_*    rpi5-node + orin-nano initrd SSH host keys
#
# NOT covered here (matches pre-2026-08-07 status quo, not a regression):
# personas/*.yaml — mac-mini's juan_signing_key/juan_gemini_api_key already
# tolerated a missing sopsFile before this cutover (validateSopsFiles =
# false), so mac-mini's dummy build behavior is unchanged either way.
set -euo pipefail

out="${1:-/tmp/dummy-secrets}"
mkdir -p "$out/initrd" "$out/nix/per-host"
echo "{}" >"$out/nix/shared.yaml"

for host in nixos-nvme core-pi orin-nano mac-mini; do
  echo "{}" >"$out/nix/per-host/${host}.yaml"
done

for host in nixos-nvme core-pi hass-pi orin-nano; do
  echo "ci-dummy-jwe-placeholder" >"$out/initrd/cryptroot_${host}.jwe"
  # Real key format in case anything parses it at build time.
  if [ ! -f "$out/initrd/ssh_host_ed25519_key_${host}" ]; then
    ssh-keygen -q -t ed25519 -N "" -C "ci-dummy" \
      -f "$out/initrd/ssh_host_ed25519_key_${host}"
  fi
done
