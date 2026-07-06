{
  config,
  myInventory,
  ...
}:

{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "nixos-nvme" = {
        credentialsFile = config.sops.templates."cloudflare-tunnel-credentials.json".path;
        originRequest = {
          noTLSVerify = true;
        };
        ingress = {
          "home.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "chat.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "code.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "n8n.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
          "cache.kleinbem.dev" = "https://${myInventory.network.nodes.caddy.ip}:443";
        };
        default = "http_status:404";
      };
    };
  };
}
