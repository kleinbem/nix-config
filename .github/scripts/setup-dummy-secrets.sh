#!/usr/bin/env bash
# Build the dummy kleinbem-secrets tree CI substitutes for the private repo
# (--override-input kleinbem-secrets). It must hold every path nix-config
# dereferences at eval/build time, or the build fails with "failed to get
# symlink metadata" even when eval-only checks pass:
#   nix/shared.yaml                  defaultSopsFile on every host
#   nix/per-host/<host>.yaml         per-host sopsFile overrides
#   initrd/cryptroot_<host>.jwe      my.boot.clevis-initrd secretFile
#   personas/contact.nix             plain Nix, imported by hosts/mac-mini/default.nix
# personas/*.yaml can stay missing (validateSopsFiles = false), but contact.nix
# is a plain import. Persona names must match personas.nix.
set -euo pipefail

out="${1:-/tmp/dummy-secrets}"
mkdir -p "$out/initrd" "$out/nix/per-host" "$out/personas"
echo "{}" >"$out/nix/shared.yaml"

for host in nixos-nvme core-pi orin-nano mac-mini; do
  echo "{}" >"$out/nix/per-host/${host}.yaml"
done
# core-pi asserts that the Caddy DNS-01 token exists whenever an inventory
# node has publicCert = true (hosts/core-pi/secrets.nix reads the key name
# from this file), so the dummy has to carry the key too.
echo "caddy_acme_cloudflare_token: dummy" >"$out/nix/per-host/core-pi.yaml"

for host in nixos-nvme core-pi hass-pi orin-nano; do
  echo "ci-dummy-jwe-placeholder" >"$out/initrd/cryptroot_${host}.jwe"
done

{
  echo "{"
  for name in martin michael-gruber thomas-schmidt daniel-meier rahul-kumar juan-gonzalez; do
    cat <<EOF
  "${name}" = {
    full-name = "CI Dummy (${name})";
    email = "${name}@ci-dummy.invalid";
    matrix-id = "@${name}:ci-dummy.invalid";
    github-account = null;
    discord-id = "0";
    oidc-subject = "${name}@ci-dummy.invalid";
    origin = "CI";
    timezone = "UTC";
    bio = "CI dummy contact — see setup-dummy-secrets.sh.";
  };
EOF
  done
  echo "}"
} >"$out/personas/contact.nix"
