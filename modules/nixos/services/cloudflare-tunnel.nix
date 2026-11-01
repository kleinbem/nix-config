{
  config,
  lib,
  myInventory,
  ...
}:

let
  cfg = config.my.services.cloudflareTunnel;
  caddy = "https://${myInventory.network.nodes.caddy.ip}:443";

  # Every `public = true` inventory node gets its `domain` routed to Caddy.
  # Mesh-only services leave `public` unset and are reached over NetBird
  # (nix/infra/netbird/dns.tf); anything else hits the 404 default.
  publicNodes = lib.filterAttrs (_: n: n.public or false) myInventory.network.nodes;
in
{
  options.my.services.cloudflareTunnel = {
    enable = lib.mkEnableOption "Cloudflare tunnel connecting public domains to the Caddy gateway";
  };

  config = lib.mkIf cfg.enable {
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
  };
}
