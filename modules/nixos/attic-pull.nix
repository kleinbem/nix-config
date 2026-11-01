# Authenticated, NetBird-routed pulls from the private Attic cache. Without
# them hosts get 401, fall back to cache.nixos.org and compile on-device.
#   Auth: a netrc entry with a password but no login, which nix sends as the
#   Bearer header Attic expects.
#   Transport: pin cache.kleinbem.dev to core-pi's mesh IP; the Cloudflare
#   tunnel's 100 MiB per-NAR cap 413s on big closures. core-pi overrides
#   cacheHostIp to caddy's local address, since traffic to its own NetBird IP
#   misses the PREROUTING DNAT.
# The cache stays private so a secret that lands in a store path isn't public.
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
      # Hosts whose resolver asks NetBird DNS set this false and follow the
      # mesh record instead of a baked IP that goes stale.
      default = true;
      description = "Pin cache.kleinbem.dev in /etc/hosts (fallback for hosts without NetBird-aware DNS).";
    };
  };

  config = lib.mkIf (config.sops.secrets ? attic_pull_token) {
    # Readable by wheel so user-run nix commands (nix copy, nix path-info
    # --store https://cache.kleinbem.dev) authenticate with the same token,
    # instead of a hand-made plaintext copy in ~/.config/nix/netrc.
    sops.templates."attic-netrc" = {
      # Both names during the rename to attic.kleinbem.dev.
      content = ''
        machine cache.kleinbem.dev
        password ${config.sops.placeholder.attic_pull_token}
        machine attic.kleinbem.dev
        password ${config.sops.placeholder.attic_pull_token}
      '';
      group = "wheel";
      mode = "0440";
    };

    nix.settings.netrc-file = config.sops.templates."attic-netrc".path;

    networking.hosts = lib.mkIf config.my.atticPull.manageHostsEntry {
      ${config.my.atticPull.cacheHostIp} = [
        "cache.kleinbem.dev"
        "attic.kleinbem.dev"
      ];
    };
  };
}
