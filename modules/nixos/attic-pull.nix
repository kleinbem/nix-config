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
#   2. TRANSPORT — resolve cache.kleinbem.dev to the cache entrypoint's IP so
#      pulls traverse the WireGuard mesh (wt0) instead of the public Cloudflare
#      tunnel, whose 100 MiB per-NAR cap 413s on big closures like the kernel.
#      The entrypoint is the caddy container on nixos-nvme, which terminates
#      TLS for cache.kleinbem.dev and proxies to the attic container on core-pi
#      (10.85.48.120:8080) over the static container-subnet routes
#      (network-routing.nix). nixos-nvme itself overrides cacheHostIp to the
#      caddy container's local address — traffic to its own NetBird IP would
#      miss the PREROUTING port-forward.
#
# Security model (deliberately private, not public): the cache stays access-
# controlled, so even if a secret ever accidentally lands in a cached store
# path it is not exposed to the internet — only to authenticated mesh peers.
#
# Inert unless the host declares the attic_pull_token secret.
{ config, lib, ... }:

{
  options.my.atticPull.cacheHostIp = lib.mkOption {
    type = lib.types.str;
    # nixos-nvme's NetBird IP (the cache entrypoint). Mirrors the /etc/hosts
    # override the CI nix-fleet-setup action applies.
    default = "100.117.212.232";
    description = "IP that cache.kleinbem.dev resolves to for authenticated NetBird-routed pulls.";
  };

  config = lib.mkIf (config.sops.secrets ? attic_pull_token) {
    sops.templates."attic-netrc".content = ''
      machine cache.kleinbem.dev
      password ${config.sops.placeholder.attic_pull_token}
    '';

    nix.settings.netrc-file = config.sops.templates."attic-netrc".path;

    networking.hosts.${config.my.atticPull.cacheHostIp} = [ "cache.kleinbem.dev" ];
  };
}
