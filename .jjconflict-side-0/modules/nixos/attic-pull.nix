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
#      The entrypoint is the caddy container on core-pi (moved off nixos-nvme
#      2026-07-06), which terminates TLS for cache.kleinbem.dev and proxies to
#      the attic container (10.85.48.120:8080) on the same host. core-pi's
#      netbird-nat nftables table DNATs wt0:{80,443} to the caddy container.
#      core-pi itself overrides cacheHostIp to the caddy container's local
#      address — its own traffic to its own NetBird IP would miss the
#      PREROUTING port-forward.
#
# Security model (deliberately private, not public): the cache stays access-
# controlled, so even if a secret ever accidentally lands in a cached store
# path it is not exposed to the internet — only to authenticated mesh peers.
#
# Inert unless the host declares the attic_pull_token secret.
{ config, lib, ... }:

let
  inv = import ../../inventory.nix;
in
{
  options.my.atticPull = {
    cacheHostIp = lib.mkOption {
      type = lib.types.str;
      # core-pi's NetBird IP (the cache entrypoint), single-sourced from
      # inventory.nix. Mirrors the fallback the CI nix-fleet-setup action uses.
      default = inv.hosts.core-pi.netbirdIp;
      description = "IP that cache.kleinbem.dev resolves to for authenticated NetBird-routed pulls.";
    };
    manageHostsEntry = lib.mkOption {
      type = lib.types.bool;
      # The static /etc/hosts pin is the fallback resolution path. Hosts whose
      # resolver consults NetBird DNS (the tofu-managed zone in
      # infra/netbird/dns.tf) set this to false — see the dnsmasq forward in
      # ai-hardening.nix — and then follow the mesh record instead of a baked
      # IP that goes stale on the next entrypoint move.
      default = true;
      description = "Pin cache.kleinbem.dev in /etc/hosts (fallback for hosts without NetBird-aware DNS).";
    };
  };

  config = lib.mkIf (config.sops.secrets ? attic_pull_token) {
    sops.templates."attic-netrc".content = ''
      machine cache.kleinbem.dev
      password ${config.sops.placeholder.attic_pull_token}
    '';

    nix.settings.netrc-file = config.sops.templates."attic-netrc".path;

    networking.hosts = lib.mkIf config.my.atticPull.manageHostsEntry {
      ${config.my.atticPull.cacheHostIp} = [ "cache.kleinbem.dev" ];
    };
  };
}
