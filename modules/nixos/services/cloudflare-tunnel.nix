{
  config,
  lib,
  myInventory,
  ...
}:

let
  caddy = "https://${myInventory.network.nodes.caddy.ip}:443";

  # Every inventory node marked `public = true` gets its `domain` on the
  # tunnel (→ Caddy, which already has a vhost for it from `externalPort`).
  # Generated rather than hand-maintained since 2026-09-26: the old literal
  # list silently missed new/renamed hostnames three times (authelia/login,
  # auth.kleinbem.dev, then 2fa.kleinbem.dev after Ente's rename), each
  # time a 404 at Cloudflare's edge that never even reached Caddy.
  #
  # Mesh-only services (code, frigate, paperless, s3, …) simply don't set
  # `public` — they're reached over NetBird via the per-FQDN DNS overrides
  # in nix/infra/netbird/dns.tf (→ core-pi mesh IP → DNAT → caddy). Retired
  # hostnames (authelia., login.) fall through to the 404 `default` below,
  # deliberately.
  publicNodes = lib.filterAttrs (_: n: n.public or false) myInventory.network.nodes;
in
{
  assertions = lib.mapAttrsToList (name: n: {
    assertion = n ? domain && n ? externalPort;
    message = "inventory node `${name}` is public = true but lacks `domain` or `externalPort` — Caddy wouldn't have a vhost for it, so the tunnel route would dead-end.";
  }) publicNodes;

  services.cloudflared = {
    enable = true;
    tunnels = {
      "core-pi" = {
        credentialsFile = config.sops.templates."cloudflare-tunnel-credentials.json".path;
        originRequest = {
          noTLSVerify = true;
        };
        ingress = {
          # Apex: the static kleinbem-site served by Caddy's staticSites —
          # not an inventory node.
          "kleinbem.dev" = caddy;
        }
        // lib.mapAttrs' (_: n: lib.nameValuePair n.domain caddy) publicNodes;
        default = "http_status:404";
      };
    };
  };
}
