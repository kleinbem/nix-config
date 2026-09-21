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
          # login.kleinbem.dev (kleinbem-auth) removed 2026-09-21 —
          # decommissioned, replaced by Authentik (auth.kleinbem.dev,
          # below). Visitors to the old URL now get the plain
          # http_status:404 `default` below, deliberately — kleinbem.dev
          # itself is where visitors actually land, not this subdomain.
          # Authentik (kleinbem-auth's replacement) — same bug class as
          # authelia/login above: this list is hand-maintained and had no
          # rule for it, so it 404'd at Cloudflare's edge (not even reaching
          # Caddy) despite Caddy itself already having a vhost for it
          # (auto-generated from inventory.nix's externalPort entries).
          # Found 2026-09-21 while applying Authentik's Phase 2 Terraform.
          "auth.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
        };
        default = "http_status:404";
      };
    };
  };
}
