{
  config,
  myInventory,
  ...
}:

{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "core-pi" = {
        credentialsFile = config.sops.templates."cloudflare-tunnel-credentials.json".path;
        originRequest = {
          noTLSVerify = true;
        };
        # Public tunnel ingress. `code` (browser IDE w/ shell — Cloudflare Access
        # was its only gate) and `frigate` (camera NVR) are mesh-only: reached
        # over NetBird via the per-FQDN DNS overrides in nix/infra/netbird/dns.tf
        # (→ core-pi mesh IP → core-pi DNAT → caddy). home/chat/n8n/grafana stay
        # public behind their existing auth — low breach value (dashboard),
        # external webhooks (n8n), or Authelia forward_auth (grafana, same
        # pattern as chat/n8n — see inventory.nix's monitoring node).
        #
        # `authelia.kleinbem.dev` itself MUST also be on this public ingress:
        # forward_auth on chat/n8n/grafana redirects the visitor's own browser
        # to it for login (?rd=...), and that redirect comes from whatever
        # network the VISITOR is on — not from core-pi's mesh membership. It
        # resolves publicly (wildcard *.kleinbem.dev CNAME → this tunnel) but
        # had no ingress rule, so it 404'd via `default` below for anyone off
        # NetBird's private DNS override (nix/infra/netbird/dns.tf) — i.e.
        # everyone except fleet devices. Bug, not by design; found 2026-09-19
        # testing grafana.kleinbem.dev's login redirect off-mesh.
        ingress = {
          "kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "home.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "chat.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "n8n.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "cache.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "ntfy.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "vault.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "grafana.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "authelia.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          # 502 until the kleinbem-auth container is enabled on core-pi.
          "login.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
        };
        default = "http_status:404";
      };
    };
  };
}
