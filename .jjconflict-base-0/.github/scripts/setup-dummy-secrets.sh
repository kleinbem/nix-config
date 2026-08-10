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
#   personas/contact.nix             hosts/mac-mini/default.nix's personasView
#
# personas/*.yaml (sops-encrypted, per-persona signing/API keys) are NOT
# covered here — mac-mini's persona secrets already tolerate a missing
# sopsFile (validateSopsFiles = false), so that part of the dummy build
# behavior is unchanged. personas/contact.nix is different: it's plain Nix
# (reverted from sops-encrypted 2026-08-09 — full-name/email are git
# commit-author identity, so they're public the moment a persona commits
# anything; see kleinbem-secrets/personas/contact.nix's own header), so
# hosts/mac-mini/default.nix `import`s it directly and unconditionally at
# eval time — validateSopsFiles doesn't apply to a plain import, so a
# missing file here fails the BUILD outright ("path ... does not exist"),
# not just a degraded eval. Names below must match nix-config/personas.nix's
# attribute names — keep in sync when a persona is added/renamed there.
set -euo pipefail

out="${1:-/tmp/dummy-secrets}"
mkdir -p "$out/initrd" "$out/nix/per-host" "$out/personas"
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
