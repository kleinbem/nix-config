# Authenticated, NetBird-routed pulls from the private Attic binary cache.
#
# core.nix lists https://cache.kleinbem.dev/system as a substituter for the
# whole fleet, but nothing provisions the credentials to READ it — so hosts get
# 401 Unauthorized and silently fall back to cache.nixos.org. Anything not on
# nixos.org (e.g. the custom linux-rpi kernel) then compiles on-device. Two
# things are required to actually use the cache, both mirroring how CI reaches
# it (.github/actions/nix-fleet-setup):
#
#   1. AUTH — a read-only pull token (sops: attic_pull_token) placed in a netrc.
#      nix sends a netrc entry that has a `password` but no `login` as an
#      `Authorization: Bearer <token>` header, which is what Attic expects. The
#      token is rendered by sops to /run/secrets (tmpfs) — never the nix store.
#
#   2. TRANSPORT — resolve cache.kleinbem.dev to the attic host's NetBird IP so
#      pulls traverse the WireGuard mesh (wt0) instead of the public Cloudflare
#      tunnel, whose 100 MiB per-NAR cap 413s on big closures like the kernel.
#
# Security model (deliberately private, not public): the cache stays access-
# controlled, so even if a secret ever accidentally lands in a cached store
# path it is not exposed to the internet — only to authenticated mesh peers.
#
# Inert unless the host declares the attic_pull_token secret (so nixos-nvme,
# the cache's entrypoint, is unaffected).
{ config, lib, ... }:

let
  # nixos-nvme's NetBird IP — the cache ENTRYPOINT, not the cache itself: the
  # caddy container on nixos-nvme terminates TLS for cache.kleinbem.dev and
  # proxies to the attic container on core-pi (10.85.48.120:8080) over the
  # static container-subnet routes (network-routing.nix). Mirrors the
  # /etc/hosts override the CI nix-fleet-setup action applies.
  atticHostNetbirdIp = "100.117.212.232";
in
lib.mkIf (config.sops.secrets ? attic_pull_token) {
  sops.templates."attic-netrc".content = ''
    machine cache.kleinbem.dev
    password ${config.sops.placeholder.attic_pull_token}
  '';

  nix.settings.netrc-file = config.sops.templates."attic-netrc".path;

  networking.hosts.${atticHostNetbirdIp} = [ "cache.kleinbem.dev" ];
}
