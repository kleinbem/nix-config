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
        # (→ core-pi mesh IP → core-pi DNAT → caddy). home/chat/n8n stay public
        # behind their existing auth — low breach value (dashboard) or external
        # webhooks (n8n).
        ingress = {
          "kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "home.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "chat.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "n8n.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "cache.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "ntfy.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
        };
        default = "http_status:404";
      };
    };
  };
}
